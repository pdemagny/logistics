# Bug Assessment: private-key blocks

A block from its begin line through its end line:

```text
@private-key@
MIIEowIBAAKCAQEA0Zq81mXv0Lw3NcR7tYp2Ue5Ha
-----END RSA PRIVATE KEY-----
done
```

A block with no end line, ended by a blank line:

@private-key@
MIIEowIBAAKCAQEA0Zq81mXv0Lw3NcR7tYp2Ue5Ha

kept after the blank line

A block with no end line, ended by a closing fence:

~~~
@private-key@
MIIEowIBAAKCAQEA0Zq81mXv0Lw3NcR7tYp2Ue5Ha
~~~

kept after the fence
