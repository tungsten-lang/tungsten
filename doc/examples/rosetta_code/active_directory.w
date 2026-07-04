use ldap

ldap = LDAP.new "ldap.tungsten-lang.org"
ldap.bind "admin", "password"

## expect skip external LDAP dependency
