# Sourced by the iPhone scripts. Sets UDID and NAME for the phone to use.
#
# The phone is picked in this order: $CUE_DEVICE (name or UDID), the one
# saved by Scripts/claude-remote.sh in .cue-device, then the first iPhone
# that is connected right now (USB before Wi-Fi).

resolve_iphone() {
	local wanted="${CUE_DEVICE:-}" devices line
	[ -z "$wanted" ] && [ -f .cue-device ] && wanted="$(cat .cue-device)"

	devices="$(Scripts/list-iphones.py)"
	[ -n "$devices" ] || fail "No iPhone connected. Plug it in (or pair it over Wi-Fi in Xcode ▸ Devices), unlock it, and make sure Developer Mode is on."

	if [ -n "$wanted" ]; then
		line="$(echo "$devices" | awk -F'\t' -v w="$wanted" '$1 == w || $2 == w' | head -1)"
		[ -n "$line" ] || fail "\"$wanted\" is not connected. Connected iPhones:
$(echo "$devices" | cut -f2-4)"
	else
		line="$(echo "$devices" | head -1)"
	fi
	UDID="$(echo "$line" | cut -f1)"
	NAME="$(echo "$line" | cut -f2)"
}
