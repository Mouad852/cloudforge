# ADR-005: SSM Session Manager for all instance access

**Status:** accepted   **Date:** 2026-09-06   **Milestone:** M1

## Context

Engineers occasionally need a shell on an EC2 instance — to debug, inspect state, or verify something a screenshot can't show. The traditional way to get there is SSH: a key pair to manage, port 22 open somewhere, and usually a bastion host in a public subnet to reach instances that live in private subnets.

This project already has a concrete example of why that surface is worth avoiding: the flow log evidence in M1 shows a constant stream of REJECT entries against the NAT instance's public IP — automated internet scanners probing it within minutes of it getting an Elastic IP, port 22 or not. Every open inbound port is something that gets probed the moment it exists.

## Decision

All instance access goes through **AWS Systems Manager Session Manager**. No key pairs are created anywhere in this project, no security group in any module opens an inbound port for interactive access, and there is no bastion host. An instance that needs to be reachable for a shell session gets:

- An IAM role with the `AmazonSSMManagedInstanceCore` managed policy attached, so the SSM agent can authenticate and register.
- A security group with **no ingress rules at all** — Session Manager doesn't need one, since the agent initiates an outbound HTTPS connection to AWS's SSM endpoints and the session rides on that same channel.
- Outbound HTTPS reachability to the SSM endpoints — via NAT for a private-subnet instance, direct via IGW for a public one.

Proven end-to-end in M1: `dev-ssm-test-instance` sits in the `app-a` private subnet with no public IP, no key pair, and a security group with zero inbound rules, and is still reachable for an interactive shell via the console's Session Manager tab.

## Alternatives considered

- **SSH with a bastion host** — the standard older pattern. Rejected: a bastion is one more instance to patch and secure, `.pem` files inevitably end up scattered across laptops with no way to revoke one person's access without rotating the shared key, and port 22 open anywhere is a permanent, actively-probed target (see the flow log evidence above).
- **SSH directly to each instance (no bastion)** — worse than a bastion: every instance needing a public IP or a more complex private-network SSH relay, and the same key-management problem multiplied across every box.
- **EC2 Instance Connect** — closer to SSM in spirit (IAM-gated, no long-lived keys), but still opens port 22 and is really built around short browser sessions rather than the general access pattern this project needs everywhere.

## Consequences

- Who can start a session on which instance is an IAM policy, not a network rule or a shared secret — grantable and revocable per person without touching any instance.
- Every session is attributable and audited via CloudTrail, unlike a shared bastion key where "who connected" is much harder to answer.
- No instance in this project needs a public IP purely to be reachable for administration — reachability for ops access and reachability from the internet are now fully decoupled.
- The trade-off: Session Manager depends on the SSM agent successfully reaching AWS's SSM endpoints. For a private-subnet instance, that means it inherits whatever is true of the NAT path at the time — when the NAT instance's forwarding rule was broken (see the known issue in ADR-008), this instance's SSM connectivity broke right along with it. A bastion with direct routing wouldn't have shared that specific failure mode, though it would have its own.
