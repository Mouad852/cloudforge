from checkov.common.models.enums import CheckCategories, CheckResult
from checkov.terraform.checks.provider.base_check import BaseProviderCheck

# The tags every CloudForge resource carries (PLAN.md, M0). Tag keys are
# case-sensitive in AWS, so "managedBy" does not count as "ManagedBy".
REQUIRED_TAGS = ("Project", "Environment", "ManagedBy", "Owner")


class ProviderDefaultTags(BaseProviderCheck):
    """Tags are set once per provider through default_tags, never per resource,
    so this checks the provider block: a resource-level tag check would flag
    every resource even when the provider tags it correctly."""

    def __init__(self):
        super().__init__(
            name="AWS provider sets the required default_tags: " + ", ".join(REQUIRED_TAGS),
            id="CKV_CF_1",
            categories=(CheckCategories.CONVENTION,),
            supported_provider=("aws",),
        )

    def scan_provider_conf(self, conf):
        # Module tests (*.tftest.hcl) declare a bare provider of their own;
        # what they create is torn down when the test ends.
        if ".tftest.hcl:" in self.entity_path:
            return CheckResult.UNKNOWN
        default_tags = conf.get("default_tags")
        if not default_tags or not isinstance(default_tags[0], dict):
            return CheckResult.FAILED
        tags = default_tags[0].get("tags")
        if not tags or not isinstance(tags[0], dict):
            return CheckResult.FAILED
        missing = [key for key in REQUIRED_TAGS if not tags[0].get(key)]
        if missing:
            self.details.append("missing default_tags: " + ", ".join(missing))
            return CheckResult.FAILED
        return CheckResult.PASSED


check = ProviderDefaultTags()
