# The matching half of tests/check-eol.sh. IN ITS OWN FILE ON PURPOSE: embedded
# in a single-quoted shell string, one apostrophe inside a comment closed the
# string and the script stopped parsing -- the third quoting mishap of the day,
# after `$"` ending a PowerShell regex and a heredoc eating `\n`. A program that
# lives in a file cannot be broken by the quoting of its caller.
#
# Input is three tagged streams, concatenated by the caller:
#   E <git ls-files --eol line>    the declaration and both actual endings
#   W <path>:<count>               worktree lines ending in CR
#   C <path>:<count>               worktree lines containing CR anywhere

function rsplitc(s, out) {          # "path:count", split at the LAST colon
  i = length(s)
  while (i > 0 && substr(s, i, 1) != ":") i--
  if (i <= 1) return 0
  out["path"] = substr(s, 1, i-1); out["count"] = substr(s, i+1) + 0
  return 1
}
function add(msg) { fails[++nf] = msg }

{ kind = substr($0, 1, 1) }

# E i/lf    w/lf    attr/text eol=lf      <TAB> path
kind == "E" {
  path = $2
  head = substr($1, 3)
  n = split(head, p, /[ \t]+/)
  idx = ""; wrk = ""; att = ""
  for (j = 1; j <= n; j++) {
    if (p[j] ~ /^i\//)         idx = substr(p[j], 3)
    else if (p[j] ~ /^w\//)    wrk = substr(p[j], 3)
    else if (p[j] ~ /^attr\//) { att = substr(p[j], 6)
                                 for (k = j+1; k <= n; k++) att = att " " p[k]
                                 break }
  }
  sub(/[ \t]+$/, "", att)
  files[++nfiles] = path; I[path] = idx; W[path] = wrk; A[path] = att
  next
}
kind == "W" { if (rsplitc(substr($0, 3), o)) wcrlf[o["path"]] = o["count"]; next }
kind == "C" { if (rsplitc(substr($0, 3), o)) wany[o["path"]]  = o["count"]; next }

END {
  for (i = 1; i <= nfiles; i++) {
    f = files[i]; idx = I[f]; wrk = W[f]; att = A[f]

    if (att == "") {
      add("UNDECLARED: " f " -- no rule in .gitattributes covers it, so its endings are whatever the cloning machine decided. Add a rule, or restore the default line if that is what went missing.")
      continue
    }
    # `binary` is a macro for -text -diff, and git reports it as attr/-text
    if (att ~ /(^| )-text( |$)/ || att ~ /(^| )binary( |$)/) { nbin++; continue }

    if (att !~ /(^| )text/) {
      add("UNDECLARED TEXTNESS: " f " has attributes (" att ") but none of them says whether it is text, so nothing decides how it is stored.")
      continue
    }

    # THE ASSERTION AN EARLIER REWRITE LOST. The verdict comes from git itself as
    # i/-text, and a file git reads as binary while .gitattributes calls it text
    # WILL be rewritten by the eol filter. That is corruption, not conversion.
    # The version that counted with `git grep -I` could not see this at all,
    # because -I skips exactly the files the assertion is about.
    if (idx == "-text") {
      add("DECLARED TEXT BUT BINARY: " f " -- .gitattributes says text (" att ") while git reads the stored content as binary. The eol filter will rewrite it. Declare it binary.")
      continue
    }
    ntext++

    if (idx == "crlf" || idx == "mixed") {
      add("BLOB IS " toupper(idx) ": " f " -- stored with CRLF in a file .gitattributes keeps as LF. The next commit that touches it rewrites every line (app.js did exactly this: 26,260 lines on a 136-line change). Fix: git add --renormalize -- " f)
    }

    # THE WORKING TREE, only where eol is declared
    if (att ~ /eol=lf/) {
      neol++
      if (wrk == "crlf" || wrk == "mixed")
        add("WORKTREE IS " toupper(wrk) ": " f " -- declared eol=lf. An in-place rewriter (sed -i) or an editor put CRLF there. Fix: rm -- " f " && git checkout -- " f)
    }
    if (att ~ /eol=crlf/) {
      neol++
      if (wrk == "lf")
        add("WORKTREE IS LF: " f " -- declared eol=crlf. Fix: rm -- " f " && git checkout -- " f)
    }
    # A LONE CR survives BOTH filters, so it is the one thing that makes a
    # CR-stripped before/after comparison lie about what a commit changed. The eol
    # vocabulary in git cannot see it: it knows LF and CRLF, and a bare CR is
    # neither, which is why the caller measures this with git grep.
    if (att ~ /eol=(lf|crlf)/) {
      wc = (f in wcrlf) ? wcrlf[f] : 0
      wa = (f in wany)  ? wany[f]  : 0
      if (wa != wc)
        add("LONE CR: " f " has CR away from end of line (" wa " line(s) with CR, " wc " ending in one). No filter converts these, so they survive every normalisation and make a CR-stripped diff untrustworthy.")
    }
  }

  # COVERAGE BEFORE THE VERDICT (D124, and the rule that a sweep of a blank page
  # passes everything): 60-odd files are tracked, so a census that examined a
  # handful examined nothing.
  if (nfiles < 40) add("VACUOUS: only " nfiles " tracked files were enumerated -- check that git ls-files ran.")
  if (ntext  < 30) add("VACUOUS: only " ntext " text files were examined. A census that reaches almost nothing passes almost anything -- check that .gitattributes still carries its default.")
  if (neol   < 1)  add("VACUOUS: no file declares eol, so the working-tree half of this check asserted nothing at all.")
  if (nbin   < 1)  add("VACUOUS: no file is declared binary, yet this repo tracks PNGs and corpus shards -- the binary half of the census is not being exercised.")

  if (nf > 0) {
    print "check-eol: FAIL"
    for (i = 1; i <= nf; i++) print "  - " fails[i]
    print "GATE: FAIL"
    exit 1
  }
  printf "check-eol: %d tracked; %d text blobs are LF, %d have their worktree endings pinned, %d binary left alone\n", nfiles, ntext, neol, nbin
  print "GATE: PASS"
}
