#!/bin/bash
set -euo pipefail

mkdir -p /opt/cloudforge /var/log/cloudforge

# AL2023's "minimal" AMI variant doesn't ship the SSM agent preinstalled -
# the standard variant does, but the AMI filter matches both and
# most_recent has picked minimal before (same class of issue as the NAT
# instance's missing iptables, ADR-008). Install explicitly so instance
# management works regardless of which variant lands.
dnf install -y amazon-ssm-agent
systemctl enable --now amazon-ssm-agent

dnf install -y amazon-cloudwatch-agent

# On a from-scratch build (the nightly destroy, a DR rebuild) the apply that
# creates this instance also creates the empty artifacts bucket, and the
# binary is uploaded right after it (scripts/ensure-artifact.sh). Wait for it
# rather than fail: user data never re-runs, so an instance whose first
# download failed would stay broken until the ASG replaced it.
for attempt in $(seq 1 90); do
  if aws s3 cp "s3://${artifacts_bucket}/${artifact_key}" /opt/cloudforge/cloudstore-api; then
    break
  fi
  if [ "$attempt" -eq 90 ]; then
    echo "artifact never appeared after 15 minutes" >&2
    exit 1
  fi
  sleep 10
done
chmod +x /opt/cloudforge/cloudstore-api

cat > /etc/systemd/system/cloudforge-api.service <<'UNIT'
[Unit]
Description=CloudForge CloudStore API
After=network.target

[Service]
Type=simple
ExecStart=/opt/cloudforge/cloudstore-api
Restart=always
RestartSec=2
TimeoutStopSec=40
KillSignal=SIGTERM
Environment=PORT=${app_port}
Environment=AWS_REGION=${aws_region}
Environment=DB_SECRET_ARN=${db_secret_arn}
Environment=REDIS_ADDR=${redis_addr}
Environment=REDIS_AUTH_SECRET_ARN=${redis_secret_arn}
Environment=REDIS_TLS_SERVER_NAME=${redis_tls_server_name}
Environment=S3_BUCKET=${images_bucket_name}
StandardOutput=append:/var/log/cloudforge/app.log

[Install]
WantedBy=multi-user.target
UNIT

cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'CONFIG'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/cloudforge/app.log",
            "log_group_name": "${log_group_name}",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  },
  "metrics": {
    "namespace": "CloudForge/EC2",
    "metrics_collected": {
      "mem": { "measurement": ["mem_used_percent"] },
      "disk": { "measurement": ["used_percent"], "resources": ["/"] }
    }
  }
}
CONFIG

systemctl enable amazon-cloudwatch-agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

systemctl daemon-reload
systemctl enable --now cloudforge-api
