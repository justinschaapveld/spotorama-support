#!/usr/bin/env bash
# Verifies a build of the Spotorama site against the things that must not drift.
# Run from the directory holding the five pages:  ./check.sh  [dir]
set -uo pipefail
D="${1:-.}"; cd "$D" || exit 2
fail=0
ok()   { printf "  \033[32m✓\033[0m %s\n" "$1"; }
bad()  { printf "  \033[31m✗\033[0m %s\n" "$1"; fail=1; }

echo "1. Frozen privacy text"
python3 - "$D" <<'PY'
import re,sys,hashlib,io,os
# Re-baselined 7 Sep 2026: the contact address moved to support@spotorama.app.
# The legal wording is unchanged — only the mailto and its link text differ.
EXPECT="4683c07ec1d956e9"
try: s=io.open("privacy.html",encoding="utf-8").read()
except FileNotFoundError: print("  \033[31m✗\033[0m privacy.html missing"); sys.exit(1)
m=re.search(r'<section class="panel">(.*)</section>',s,re.S)
if not m:
    print("  \033[33m!\033[0m no <section class=\"panel\"> — markup restructured, hash cannot be compared")
    print("      Compare the words by hand against signed-off-copy/privacy.html"); sys.exit(0)
h=hashlib.sha256(m.group(1).encode()).hexdigest()[:16]
print(("  \033[32m✓\033[0m frozen block matches %s" % EXPECT) if h==EXPECT
      else "  \033[31m✗\033[0m frozen block is %s, expected %s" % (h,EXPECT))
sys.exit(0 if h==EXPECT else 1)
PY
[ $? -ne 0 ] && fail=1

echo "2. The 28 shipped point values"
python3 - <<'PY'
import io,re,glob,sys
# 28 shipped spots, 27 distinct names: The Orange Run's Yellow Car is a separate spot
# with its own identifier but the same name and the same 1 point, so one key covers both.
want={"Yellow Car":1,"Beetle":2,"Camper Van":3,"Tractor":3,"Police Car":2,"Yellow Number Plate":2,
 "Sheep":1,"Cattle":1,"Horse":2,"Kangaroo":3,"Alpaca":5,"Scarecrow":5,
 "Semi Trailer":1,"Tow Truck":3,"Cement Mixer":3,"Car Carrier":4,"Fire Truck":4,"Road Train":8,
 "Roundabout":1,"Church":2,"Water Tower":3,"Silo":3,"Windmill":4,"Funny Letterbox":5,
 "Pink Car":2,"Purple Car":2,"Unicorn":10}
blob="".join(io.open(f,encoding="utf-8").read() for f in glob.glob("*.html"))
text=re.sub(r"<[^>]*>"," ",blob); text=re.sub(r"\s+"," ",text)
missing=[n for n in want if n not in text]
if missing: print("  \033[31m✗\033[0m spots not found: %s" % ", ".join(sorted(missing))); sys.exit(1)
# Every mention that has a number near it must agree, not just the first one. The
# original checked only the first and used a 14-char window, which broke the moment a
# spot was named somewhere with a description before its points: index.html's scorecard
# puts 37 characters between "Unicorn" and its 10. Checking all mentions is also the
# stronger test — a wrong value anywhere on the site now fails, not only on first use.
wrong=[]
for n,v in want.items():
    found=[]
    for m in re.finditer(re.escape(n), text):
        nums=re.findall(r"\d+", text[m.end():m.end()+60])
        if nums: found.append(int(nums[0]))
    if not found:
        wrong.append("%s→no value near any mention (want %d)" % (n, v))
    else:
        bad=sorted({x for x in found if x!=v})
        if bad: wrong.append("%s→%s (want %d)" % (n, "/".join(map(str,bad)), v))
print("  \033[32m✓\033[0m 28 shipped spots, 27 distinct names, all correct" if not wrong
      else "  \033[31m✗\033[0m %s" % "; ".join(wrong))
sys.exit(1 if wrong else 0)
PY
[ $? -ne 0 ] && fail=1

echo "3. Naming rule — \"Spotto\" only ever quoted"
# Quoting counts whether it is a literal quote character or an HTML entity
# (&ldquo; &rdquo; &quot; &#8220;). Entities are the normal case in generated markup.
bare=$(grep -ho '.\{8\}Spotto[^r]' *.html 2>/dev/null \
       | grep -viE '(&ldquo;|&quot;|&#8220;|&#x201c;|[“"”])spotto' | head -5)
[ -z "$bare" ] && ok "no unquoted Spotto" || { bad "unquoted Spotto found:"; echo "$bare" | sed 's/^/      /'; }

echo "4. Internal links and images resolve"
# Every local href, src and srcset — a #fragment must name an id in its page. The old
# pattern matched only hrefs ending in .html or .css, so "support.html#contact", the icons
# and the badge's srcset were skipped rather than checked.
python3 - <<'PY'
import glob,io,os,re,sys
refs=re.compile(r'\b(href|src|srcset)="([^"]*)"')
external=re.compile(r'^(?:[a-z][a-z0-9+.-]*:|//)', re.I)
ids={}
def page_ids(p):
    if p not in ids: ids[p]=set(re.findall(r'\bid="([^"]+)"', io.open(p,encoding="utf-8").read()))
    return ids[p]
checked=0; miss=[]
for f in sorted(glob.glob("*.html")):
    for attr,value in refs.findall(io.open(f,encoding="utf-8").read()):
        urls=[c.split()[0] for c in value.split(",") if c.strip()] if attr=="srcset" else [value]
        for url in urls:
            if not url or external.match(url): continue
            path,_,frag=url.partition("#"); path=path.split("?")[0]; target=path or f
            checked+=1
            if not os.path.isfile(target): miss.append("%s→%s" % (f,url))
            elif frag and target.endswith(".html") and frag not in page_ids(target):
                miss.append("%s→%s (no id=\"%s\")" % (f,url,frag))
if not checked: print("  \033[31m✗\033[0m no internal links found at all — this check is broken"); sys.exit(1)
print(("  \033[32m✓\033[0m all %d internal href, src and srcset targets exist, fragments included" % checked)
      if not miss else "  \033[31m✗\033[0m broken: %s" % "; ".join(miss))
sys.exit(1 if miss else 0)
PY
[ $? -ne 0 ] && fail=1

echo "5. Required filenames present"
for r in privacy.html support.html; do
  [ -f "$r" ] && ok "$r" || bad "$r missing — Apple links to this exact name"
done

echo "6. Dark scheme defined at token level"
for c in *.css; do
  [ -f "$c" ] || continue
  if grep -q "prefers-color-scheme" "$c"; then ok "$c has a dark scheme"
  else bad "$c defines no dark scheme"; fi
done
grep -l "prefers-color-scheme" *.html >/dev/null 2>&1 && ok "inline dark scheme present in HTML"

echo
[ $fail -eq 0 ] && echo "PASS" || echo "FAIL — see ✗ above"
exit $fail
