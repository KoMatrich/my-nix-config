/* iphone-wifi-sync on|off|status
 *
 * Flips the iPhone's "Show this iPhone when on Wi-Fi" switch (lockdown key
 * com.apple.mobile.wireless_lockdown/EnableWifiConnections) - the setting
 * iTunes/Finder toggle. libimobiledevice ships no CLI that writes it, and
 * pymobiledevice3 doesn't evaluate on our nixpkgs, hence this helper.
 * Needs the phone on USB and already paired (`idevicepair pair`).
 */
#include <stdio.h>
#include <string.h>
#include <libimobiledevice/libimobiledevice.h>
#include <libimobiledevice/lockdown.h>
#include <plist/plist.h>

#define DOMAIN "com.apple.mobile.wireless_lockdown"
#define KEY "EnableWifiConnections"

int main(int argc, char **argv)
{
	if (argc != 2 || (strcmp(argv[1], "on") && strcmp(argv[1], "off") && strcmp(argv[1], "status"))) {
		fprintf(stderr, "usage: %s on|off|status\n", argv[0]);
		return 2;
	}

	idevice_t dev = NULL;
	if (idevice_new_with_options(&dev, NULL, IDEVICE_LOOKUP_USBMUX) != IDEVICE_E_SUCCESS) {
		fprintf(stderr, "No iPhone found on USB. Plug it in, unlock it and tap \"Trust\".\n");
		return 1;
	}

	lockdownd_client_t ld = NULL;
	lockdownd_error_t err = lockdownd_client_new_with_handshake(dev, &ld, "iphone-wifi-sync");
	if (err != LOCKDOWN_E_SUCCESS) {
		fprintf(stderr, "Could not open a trusted session (lockdown error %d). Run `idevicepair pair` first.\n", err);
		idevice_free(dev);
		return 1;
	}

	int rc = 0;
	if (strcmp(argv[1], "status")) {
		/* lockdownd_set_value takes ownership of the plist node */
		err = lockdownd_set_value(ld, DOMAIN, KEY, plist_new_bool(!strcmp(argv[1], "on")));
		if (err != LOCKDOWN_E_SUCCESS) {
			fprintf(stderr, "Setting %s failed (lockdown error %d).\n", KEY, err);
			rc = 1;
		}
	}

	plist_t val = NULL;
	if (lockdownd_get_value(ld, DOMAIN, KEY, &val) == LOCKDOWN_E_SUCCESS && val && plist_get_node_type(val) == PLIST_BOOLEAN) {
		uint8_t on = 0;
		plist_get_bool_val(val, &on);
		printf("Wi-Fi connections: %s\n", on ? "on" : "off");
	} else {
		printf("Wi-Fi connections: unknown (never set)\n");
	}
	plist_free(val);

	lockdownd_client_free(ld);
	idevice_free(dev);
	return rc;
}
