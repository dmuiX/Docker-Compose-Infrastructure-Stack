# === USERS ===
# Create user
docker exec samba-dc samba-tool user create max MyPass123! -UAdministrator%"$PASS"
# IMPORTANT: Email for totp necessary...for any weird reason
# Create user with email

docker exec samba-dc samba-tool user create webdav 'DeinSicheresPasswort123!' \
  --given-name='Web' --surname='Dav' \
  --mail-address='webdav@domain.org' \
  -UAdministrator%"$PASS"

# List users
docker exec samba-dc samba-tool user list -UAdministrator%"$PASS"

# Reset password
docker exec samba-dc samba-tool user setpassword max --newpassword="NewPass!" -UAdministrator%"$PASS"

# === GROUPS ===
# Add to Domain Admins (make yourself admin)
docker exec samba-dc samba-tool group addmembers "Domain Admins" max -UAdministrator%"$PASS"

# === DNS ===
# Add service
docker exec samba-dc samba-tool dns add 127.0.0.1 domain.org myservice A 192.168.1.5 -UAdministrator%"$PASS"

# Check service
docker exec samba-dc samba-tool dns query 127.0.0.1 domain.org myservice ALL -UAdministrator%"$PASS"

# === HEALTH ===
# Check domain
docker exec samba-dc samba-tool domain info 127.0.0.1 -UAdministrator%"$PASS"

