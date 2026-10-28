# Overleaf: upload this file beside both .tex files, references.bib,
# sn-jnl.cls, sn-mathphys-ay.bst and figures/*.pdf. Select pdfLaTeX and either main file.
# No pre-generated .aux, .bbl or document PDFs need to be uploaded.
$pdf_mode = 1;

use File::Copy ();
use File::Path ();

sub subsampling_xr_read {
    my ($path) = @_;
    return '' unless -f $path;
    open my $handle, '<', $path or die "Cannot read $path: $!\n";
    local $/;
    return <$handle>;
}

sub subsampling_xr_build {
    my ($document, $directory) = @_;
    my $console = "$directory/$document-build.log";
    my $status;
    {
        local *STDOUT;
        local *STDERR;
        open STDOUT, '>', $console or die "Cannot write $console: $!\n";
        open STDERR, '>&', \*STDOUT or die "Cannot redirect stderr: $!\n";
        # -norc prevents these child builds from loading this file recursively.
        # Keep source-based job names even when Overleaf uses -jobname=output.
        $status = system('latexmk', '-norc', '-pdf',
                         '-interaction=nonstopmode', '-halt-on-error',
                         '-file-line-error', "-outdir=$directory",
                         "$document.tex");
    }
    if ($status != 0) {
        my @lines = split /\n/, subsampling_xr_read($console);
        print STDERR join("\n", @lines[(@lines > 30 ? $#lines - 29 : 0) .. $#lines]), "\n"
            if @lines;
        die "Cross-reference build failed for $document; see $console.\n";
    }
    my $generated = "$directory/$document.aux";
    die "Cross-reference build did not produce $generated.\n" unless -f $generated;
    # Do not change timestamps when the reference data have not changed.
    if (subsampling_xr_read($generated) ne subsampling_xr_read("$document.aux")) {
        File::Copy::copy($generated, "$document.aux")
            or die "Cannot copy $generated: $!\n";
    }
}

sub subsampling_xr_prepare {
    my @documents = ('manuscript', 'ESM_1');
    my $directory = '_xr';
    File::Path::make_path($directory);
    foreach my $document (@documents) {
        die "Missing $document.tex: upload both document sources.\n"
            unless -f "$document.tex";
    }

    # Both documents import labels from the other. Update them in sequence
    # until their reference data agree, rather than recursively invoking
    # a tex-to-aux dependency in both directions. Child latexmk builds also
    # track bibliography, style and figure changes and reuse cached outputs.
    for my $round (1 .. 6) {
        my $before = join("\0", map { subsampling_xr_read("$_.aux") } @documents);
        foreach my $document (@documents) {
            subsampling_xr_build($document, $directory);
        }
        my $after = join("\0", map { subsampling_xr_read("$_.aux") } @documents);
        if ($after eq $before) {
            print "Cross-document references ready (round $round).\n";
            return;
        }
    }
    die "Cross-document references did not stabilize; inspect _xr/*.log.\n";
}

# RC files are read before latexmk has parsed its job name and output folder.
# Prepare source-named AUX files here; the outer build then uses them with
# any Overleaf job name/output folder. Leave local help and cleanup alone.
unless (grep { /\A-(?:c|C|CA|h|help|v|version)\z/ } @ARGV) {
    subsampling_xr_prepare();
}
