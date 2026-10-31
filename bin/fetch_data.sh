#!/usr/bin/env bash
# fetch_data.sh - download, verify and derive the input data for germline-variant-benchmark.
#
# Usage (run from the repository root):
#   bin/fetch_data.sh full       # truth, reference, chr20 reads (+ FASTQ), stratifications (~3 GB)
#   bin/fetch_data.sh ci         # minimal CI dataset from the GitHub Release (~39 MB)
#   bin/fetch_data.sh build-ci   # rebuild the CI dataset from the full data (maintainers only)
#
# Every file is verified against a published or recorded checksum.
# Files that already exist are not downloaded again, but they are always re-verified.
# The script stops at the first error. See docs/data.md for sources and decisions.
set -euo pipefail

DATA_DIR="${DATA_DIR:-data}"

# ---------------------------------------------------------------------------
# Pinned container images (tag + digest)
# ---------------------------------------------------------------------------
SAMTOOLS_IMG="quay.io/biocontainers/samtools:1.24--h9dcdb79_1@sha256:a130447589651ed09252aa95a5e4f4132942cdb54d835d81a04a9a930d656561"
BCFTOOLS_IMG="quay.io/biocontainers/bcftools:1.24--h118bc1c_4@sha256:186c45de3059dbb1837006c27788284c89d17f8e693e7804624b6cf6ca5caca0"

# ---------------------------------------------------------------------------
# Sources and checksums
# ---------------------------------------------------------------------------
TRUTH_URL="https://ftp-trace.ncbi.nlm.nih.gov/ReferenceSamples/giab/release/AshkenazimTrio/HG002_NA24385_son/v5.0q"
TRUTH_FILES=(HG002_GRCh38_v5.0q_smvar.vcf.gz HG002_GRCh38_v5.0q_smvar.vcf.gz.tbi HG002_GRCh38_v5.0q_smvar.benchmark.bed)

REF_URL="https://ftp-trace.ncbi.nlm.nih.gov/ReferenceSamples/giab/release/references/GRCh38"
REF_FILE="GRCh38_GIABv3_no_alt_analysis_set_maskedGRC_decoys_MAP2K3_KMT2C_KCNJ18.fasta.gz"
REF_SHA256="b37cb9a9c0f8716fdb13e2c5c60f08cb8be40de39c3088176f1f62d9e8eeeed8"  # recorded by us; GIAB publishes none

BAM_URL="https://storage.googleapis.com/deepvariant/case-study-testdata"
BAM_FILE="HG002.novaseq.pcr-free.35x.dedup.grch38_no_alt.chr20.bam"
BAM_MD5_B64="jxpUGjSIA+MEJ1NZrFLaVw=="  # published by Google Cloud Storage (x-goog-hash)
EXPECTED_PAIRS=9462450

STRAT_URL="https://ftp-trace.ncbi.nlm.nih.gov/ReferenceSamples/giab/release/genome-stratifications/v3.6/GRCh38@all"
STRAT_IDS="notinalldifficultregions alldifficultregions AllHomopolymers_ge7bp_imperfectge11bp_slop5 AllTandemRepeats segdups lowmappabilityall gc15_slop50 gc85_slop50"

CI_URL="https://github.com/leorosas7777/germline-variant-benchmark/releases/download/testdata-v1/germline-ci-testdata-v1.tar.gz"
CI_SHA256="6f7f8bc2ae3cc5da2e58f63b9e77eb43633d78a07a1af5854b047ea9e0938791"
CI_REGION="chr20:10000000-11000000"   # 1-based, inclusive (VCF convention)
CI_BED_START=9999999                  # same region, 0-based (BED convention)
CI_BED_END=11000000
CI_EXPECTED_PAIRS=130069

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

# fetch URL DEST: download only if DEST does not exist yet
fetch() {
    if [[ -s "$2" ]]; then
        log "exists, skipping download: $2"
    else
        log "downloading: $1"
        curl -fSL --retry 3 -o "$2.part" "$1"
        mv "$2.part" "$2"
    fi
}

# run_in IMAGE CMD...: run a command inside a pinned container, with DATA_DIR mounted at /data
run_in() {
    local img=$1; shift
    docker run --rm -u "$(id -u):$(id -g)" -v "$DATA_ABS":/data "$img" "$@"
}

count_reads() { echo $(( $(zcat "$1" | wc -l) / 4 )); }

# check_pairs R1 R2 EXPECTED: same number of reads, equal to EXPECTED, and identical names in the same order
check_pairs() {
    local n1 n2
    gzip -t "$1" && gzip -t "$2" || die "corrupted FASTQ: $1 / $2"
    n1=$(count_reads "$1"); n2=$(count_reads "$2")
    [[ "$n1" == "$3" && "$n2" == "$3" ]] || die "pair count mismatch: R1=$n1 R2=$n2 expected=$3"
    cmp -s <(zcat "$1" | awk 'NR%4==1') <(zcat "$2" | awk 'NR%4==1') || die "R1/R2 read names are not paired"
    log "FASTQ OK: $3 pairs, names paired"
}

# clip_bed START END: keep chr20 intervals overlapping [START, END) and trim them to it (BED, 0-based)
clip_bed() {
    awk -v S="$1" -v E="$2" 'BEGIN{OFS="\t"} $1=="chr20" && $3>S && $2<E {print $1, ($2>S?$2:S), ($3<E?$3:E)}'
}

# ---------------------------------------------------------------------------
# Full dataset
# ---------------------------------------------------------------------------
fetch_truth() {
    local d="$DATA_DIR/truth"
    mkdir -p "$d"
    for f in "${TRUTH_FILES[@]}" checksum.md5 NIST_HG002_v5.0q_variant-benchmarksets_README.md; do
        fetch "$TRUTH_URL/$f" "$d/$f"
    done
    # checksum.md5 lists many files we do not use (and one line has a corrupted name),
    # so we verify only the lines for our files, matched by exact name.
    (
        cd "$d"
        for f in "${TRUTH_FILES[@]}"; do
            awk -v f="$f" '{n=$NF; sub(/^\.\//, "", n); if (n == f) print}' checksum.md5
        done | md5sum -c -
    ) || die "truth checksum failed"
}

fetch_reference() {
    local d="$DATA_DIR/reference"
    mkdir -p "$d"
    fetch "$REF_URL/$REF_FILE" "$d/$REF_FILE"
    echo "$REF_SHA256  $d/$REF_FILE" | sha256sum -c - || die "reference checksum failed"
}

fetch_reads() {
    local d="$DATA_DIR/reads" got
    mkdir -p "$d"
    fetch "$BAM_URL/$BAM_FILE" "$d/$BAM_FILE"
    fetch "$BAM_URL/$BAM_FILE.bai" "$d/$BAM_FILE.bai"
    got=$(openssl dgst -md5 -binary "$d/$BAM_FILE" | base64)
    [[ "$got" == "$BAM_MD5_B64" ]] || die "BAM md5 mismatch: got $got"
    log "BAM OK (md5 $got)"

    if [[ ! -s "$d/HG002_chr20_R1.fastq.gz" || ! -s "$d/HG002_chr20_R2.fastq.gz" ]]; then
        log "converting BAM to paired FASTQ (collate by name, drop pairs with a missing mate)"
        run_in "$SAMTOOLS_IMG" sh -c "samtools collate -@4 -u -O -T /data/reads/collate_tmp /data/reads/$BAM_FILE \
            | samtools fastq -@4 -n -1 /data/reads/HG002_chr20_R1.fastq.gz -2 /data/reads/HG002_chr20_R2.fastq.gz \
              -0 /dev/null -s /dev/null -"
    fi
    check_pairs "$d/HG002_chr20_R1.fastq.gz" "$d/HG002_chr20_R2.fastq.gz" "$EXPECTED_PAIRS"
}

fetch_stratifications() {
    local d="$DATA_DIR/stratifications" id path
    mkdir -p "$d"
    fetch "$STRAT_URL/GRCh38-all-stratifications.tsv" "$d/GRCh38-all-stratifications.tsv"
    fetch "$STRAT_URL/GRCh38-genome-stratifications-md5s.txt" "$d/GRCh38-genome-stratifications-md5s.txt"
    awk -F'\t' -v ids="$STRAT_IDS" 'BEGIN{n=split(ids, a, " "); for (i=1; i<=n; i++) k[a[i]]=1} ($1 in k)' \
        "$d/GRCh38-all-stratifications.tsv" > "$d/selected-stratifications.tsv"
    [[ $(wc -l < "$d/selected-stratifications.tsv") -eq 8 ]] || die "expected 8 stratifications"
    while IFS=$'\t' read -r id path; do
        mkdir -p "$d/$(dirname "$path")"
        fetch "$STRAT_URL/$path" "$d/$path"
    done < "$d/selected-stratifications.tsv"
    (
        cd "$d"
        grep -F -f <(cut -f2 selected-stratifications.tsv) GRCh38-genome-stratifications-md5s.txt | md5sum -c -
    ) || die "stratification checksum failed"
}

# ---------------------------------------------------------------------------
# CI dataset
# ---------------------------------------------------------------------------
fetch_ci() {
    local tarball="$DATA_DIR/germline-ci-testdata-v1.tar.gz"
    mkdir -p "$DATA_DIR/ci"
    fetch "$CI_URL" "$tarball"
    echo "$CI_SHA256  $tarball" | sha256sum -c - || die "CI dataset checksum failed"
    tar -xzf "$tarball" -C "$DATA_DIR/ci"
    check_pairs "$DATA_DIR/ci/HG002_ci_R1.fastq.gz" "$DATA_DIR/ci/HG002_ci_R2.fastq.gz" "$CI_EXPECTED_PAIRS"
}

build_ci() {
    local ci="$DATA_DIR/ci" bam="/data/reads/$BAM_FILE" id path
    mkdir -p "$ci/stratifications"

    log "reference: chr20 only"
    run_in "$SAMTOOLS_IMG" sh -c "samtools faidx /data/reference/$REF_FILE \
        && samtools faidx /data/reference/$REF_FILE chr20 > /data/ci/chr20.fa \
        && samtools faidx /data/ci/chr20.fa"

    log "reads: complete pairs touching $CI_REGION (mates outside the region are kept)"
    run_in "$SAMTOOLS_IMG" sh -c "samtools view -F 0x900 $bam $CI_REGION | cut -f1 | sort -u > /data/ci/region_read_names.txt \
        && samtools view -u -N /data/ci/region_read_names.txt $bam \
        | samtools collate -u -O -T /data/ci/collate_tmp - \
        | samtools fastq -n -1 /data/ci/HG002_ci_R1.fastq.gz -2 /data/ci/HG002_ci_R2.fastq.gz -0 /dev/null -s /dev/null -"
    check_pairs "$ci/HG002_ci_R1.fastq.gz" "$ci/HG002_ci_R2.fastq.gz" "$CI_EXPECTED_PAIRS"

    log "truth: VCF and benchmark BED clipped to $CI_REGION"
    run_in "$BCFTOOLS_IMG" sh -c "bcftools view -r $CI_REGION -Oz -o /data/ci/truth_ci.vcf.gz /data/truth/${TRUTH_FILES[0]} \
        && bcftools index -f -t /data/ci/truth_ci.vcf.gz"
    clip_bed "$CI_BED_START" "$CI_BED_END" < "$DATA_DIR/truth/${TRUTH_FILES[2]}" > "$ci/truth_ci.bed"

    log "stratifications clipped to $CI_REGION"
    : > "$ci/stratifications/ci-stratifications.tsv"
    while IFS=$'\t' read -r id path; do
        mkdir -p "$ci/stratifications/$(dirname "$path")"
        zcat "$DATA_DIR/stratifications/$path" | clip_bed "$CI_BED_START" "$CI_BED_END" | gzip -n > "$ci/stratifications/$path"
        printf '%s\t%s\n' "$id" "$path" >> "$ci/stratifications/ci-stratifications.tsv"
    done < "$DATA_DIR/stratifications/selected-stratifications.tsv"

    log "packaging (reproducible tar: fixed order, mtime and owner)"
    tar --sort=name --mtime='2026-10-30 00:00:00' --owner=0 --group=0 --numeric-owner -C "$ci" -cf - \
        chr20.fa chr20.fa.fai HG002_ci_R1.fastq.gz HG002_ci_R2.fastq.gz \
        truth_ci.vcf.gz truth_ci.vcf.gz.tbi truth_ci.bed stratifications \
        | gzip -n -9 > "$DATA_DIR/germline-ci-testdata-new.tar.gz"
    sha256sum "$DATA_DIR/germline-ci-testdata-new.tar.gz"
    log "upload it as a NEW release (testdata-vN+1) and update CI_URL/CI_SHA256; never replace a published asset"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    mkdir -p "$DATA_DIR"
    DATA_ABS="$(cd "$DATA_DIR" && pwd)"
    case "${1:-}" in
        full)     fetch_truth; fetch_reference; fetch_reads; fetch_stratifications; log "full dataset ready" ;;
        ci)       fetch_ci; log "CI dataset ready in $DATA_DIR/ci" ;;
        build-ci) build_ci ;;
        *)        sed -n '2,11p' "$0"; exit 1 ;;
    esac
}

main "$@"
