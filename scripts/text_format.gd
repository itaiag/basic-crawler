class_name TextFmt extends RefCounted

# Pure, stateless text helpers shared across combat, the combat panel, and the
# status bar. No node or game state -- safe to call statically from anywhere.


static func cap(s: String) -> String:
	if s.is_empty():
		return s
	return s.substr(0, 1).to_upper() + s.substr(1)


# Signed term with a space, e.g. "+ 2" / "- 1", for readable roll breakdowns.
static func signed(n: int) -> String:
	if n >= 0:
		return "+ %d" % n
	return "- %d" % (-n)
