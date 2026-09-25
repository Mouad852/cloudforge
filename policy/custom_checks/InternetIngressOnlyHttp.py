from checkov.common.models.enums import CheckCategories, CheckResult
from checkov.terraform.checks.resource.base_resource_check import BaseResourceCheck

INTERNET = {"0.0.0.0/0", "::/0"}
# ADR-025: the ALB is the public edge and listens on HTTP only. Nothing else
# in the project is reachable from the internet.
ALLOWED_PORT = 80


def _first(value):
    # checkov wraps every HCL attribute in a list
    return value[0] if isinstance(value, list) and value else value


def _as_list(value):
    value = _first(value)
    if value is None:
        return []
    return value if isinstance(value, list) else [value]


def _is_allowed(rule):
    from_port = str(_first(rule.get("from_port")))
    to_port = str(_first(rule.get("to_port")))
    protocol = str(_first(rule.get("ip_protocol", rule.get("protocol")))).lower()
    return from_port == to_port == str(ALLOWED_PORT) and protocol in ("tcp", "6")


def _opens_to_internet(rule):
    cidrs = (
        _as_list(rule.get("cidr_blocks"))
        + _as_list(rule.get("ipv6_cidr_blocks"))
        + _as_list(rule.get("cidr_ipv4"))
        + _as_list(rule.get("cidr_ipv6"))
    )
    return any(cidr in INTERNET for cidr in cidrs)


class InternetIngressOnlyHttp(BaseResourceCheck):
    """An allowlist rather than checkov's per-port denylist (22, 3389, 80...):
    any ingress rule open to the internet fails unless it is TCP port 80."""

    def __init__(self):
        super().__init__(
            name="Ingress from the internet is only allowed on TCP port 80",
            id="CKV_CF_2",
            categories=(CheckCategories.NETWORKING,),
            supported_resources=(
                "aws_security_group",
                "aws_security_group_rule",
                "aws_vpc_security_group_ingress_rule",
            ),
        )

    def scan_resource_conf(self, conf):
        if self.entity_type == "aws_security_group":
            rules = [r for r in conf.get("ingress", []) if isinstance(r, dict)]
        elif self.entity_type == "aws_security_group_rule":
            rules = [conf] if _first(conf.get("type")) == "ingress" else []
        else:
            rules = [conf]

        for rule in rules:
            if _opens_to_internet(rule) and not _is_allowed(rule):
                return CheckResult.FAILED
        return CheckResult.PASSED


check = InternetIngressOnlyHttp()
