# Experimental patches

`priority1-push-descriptor-cache.patch` is an unchanged copy of the patch supplied
by the user. It only reduces repeated push-descriptor writes. It is not applied
to the current runtime and is not a complete binding/resource cache.

SHA-256: `f51d7447db57d1f85eb54c90b9fbe7ae785035449b2dfe547437bbedad799190`.
The patch is preserved verbatim, including single-space context markers and
its final context line. Do not apply trailing-whitespace cleanup to this artifact.

Applicability checks passed against runtime commits `81b62116` and `1e2a7566`.
Recheck applicability after further runtime changes before use. This patch
has not passed a full emulator build or gameplay tests; successful builds of
other changes do not validate it.

See [the detailed review](../PERFORMANCE_ROADMAP.md) before considering it.
