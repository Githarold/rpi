#!/bin/bash

echo "Checking Bluetooth status..."
sudo systemctl status bluetooth

echo "Checking MIE Printer service status..."
sudo systemctl status mie-printer.service

echo "Checking service logs..."
tail -n 50 ~/rpi/logs/printer.log

echo "Checking permissions..."
groups $USER
ls -l /dev/ttyUSB0