import re
from django_hosts import patterns, host

host_patterns = patterns(
    "",
    host(
        re.sub(r"_", r"-", r"abac_permissions_demo"),
        "abac_permissions_demo.urls",
        name="abac_permissions_demo",
    ),
)
