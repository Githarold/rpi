import bluetooth

print("Scanning for bluetooth devices:")
devices = bluetooth.discover_devices(lookup_names=True)
print("Found {} devices.".format(len(devices)))

for addr, name in devices:
    print("  {} - {}".format(addr, name))
