/* ARexx: One-pass Filter and Escape */
options results

parse arg inputFile outputFile .

if inputFile = "" | outputFile = "" then do
    say "Usage: rx FixScript.rexx <inputfile> <outputfile>"
    exit
end

if ~open(in, inputFile, 'R') then exit
if ~open(out, outputFile, 'W') then exit

do while ~eof(in)
    line = readln(in)
    if line = "" then iterate

    /* 1. The Exclusion: Skip lines containing '+  Emulators' */
    if pos("+  Emulators", line) > 0 then iterate

/* 2. Replace ( and ) with #? */
    /* We do this before escaping backticks to keep logic clean */
    do while pos("(", line) > 0
        p = pos("(", line)
        line = delstr(line, p, 1)
        line = insert("#?", line, p-1)
    end
    do while pos(")", line) > 0
        p = pos(")", line)
        line = delstr(line, p, 1)
        line = insert("#?", line, p-1)
    end

/* NEW: Escape single quotes: Replace ' with '' */
    newline = ""
    do while pos("'", line) > 0
        parse var line prefix "'" line
        newline = newline || prefix || "''"
    end
    line = newline || line

    /* 2. The Escape: Use 'parse var' to swap ` for `` rapidly */
    newline = ""
    do while pos("`", line) > 0
        parse var line prefix "`" line
        newline = newline || prefix || "``"
    end
    line = newline || line

    /* 3. Write the cleaned line */
    writeln(out, line)
end

close(in)
close(out)
say "Finished! Your file is ready in " || outputFile
exit