#!/bin/bash

echo "Discovering Sonos speakers on the local network..."

# Discover Sonos services via Bonjour (mDNS)
dns-sd -B _sonos._tcp local &

# Let it run for a few seconds
sleep 5

# Stop background discovery
kill $!

echo
echo "To resolve details of a discovered device, use:"
echo "dns-sd -L <InstanceName> _sonos._tcp local"