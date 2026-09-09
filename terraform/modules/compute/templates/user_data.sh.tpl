#!/bin/bash
set -euo pipefail

mkdir -p /opt/cloudforge /var/log/cloudforge

dnf install -y amazon-cloudwatch-agent

aws s3 cp "s3://${artifacts_bucket}/${artifact_key}" /opt/cloudforge/cloudstore-api
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
StandardOutput=append:/var/log/cloudforge/app.log
StandardError=append:/var/log/cloudforge/app.log

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
