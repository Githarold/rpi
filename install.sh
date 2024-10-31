#!/bin/bash

sudo apt-get update
sudo apt-get install -y python3-serial python3-bluez

sudo cp mie-printer.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable mie-printer.service

sudo sed -i 's/Name = .*/Name = MIE Printer/' /etc/bluetooth/main.conf
sudo sed -i 's/#DiscoverableTimeout = 0/DiscoverableTimeout = 0/' /etc/bluetooth/main.conf
sudo sed -i 's/#Discoverable = false/Discoverable = true/' /etc/bluetooth/main.conf
sudo sed -i 's/#Pairable = true/Pairable = true/' /etc/bluetooth/main.conf

sudo usermod -a -G dialout,bluetooth $USER

chmod -R 777 logs
chmod -R 777 gcode_files

sudo systemctl restart bluetooth
sudo systemctl start mie-printer.service

echo "Installation completed. Please reboot the system."