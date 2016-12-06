#!/bin/sh

cp d4-demo-*.service /lib/systemd/system/

systemctl enable d4-demo-network-rules.service
systemctl start d4-demo-network-rules.service

cp -r template/* /etc/
