# Input data

This page documents every input the pipeline uses: where it comes from, which exact version,
how it is verified, and why it was chosen. Data files are **not** stored in this repository;
`bin/fetch_data.sh` downloads, verifies and derives all of them.

```bash
bin/fetch_data.sh full       # full chr20 benchmark data (~3 GB)
bin/fetch_data.sh ci         # minimal CI dataset (~39 MB, from a GitHub Release)
```

Requirements: `bash`, `curl`, `openssl`, `gzip`, `awk`, `md5sum`/`sha256sum`, and Docker
(samtools and bcftools run from pinned containers).

## Overview

| Input | Source | Version | Verification |
|---|---|---|---|
| Truth variants + confident regions | GIAB (NIST) | HG002 **v5.0q** `smvar`, GRCh38 | md5 published by GIAB |
| Reference genome | GIAB (NIST) | **GRCh38 GIABv3** (no-alt, masked, decoys) | sha256 recorded by us |
| Sequencing reads | Google DeepVariant case-study data | HG002 NovaSeq PCR-free, chr20 | md5 published by Google Cloud Storage |
| Stratifications | GIAB (NIST) | **v3.6**, 8 regions | md5 published by GIAB |
| CI dataset | This repository (GitHub Release) | `testdata-v1` | sha256 recorded by us |

## Truth set: GIAB HG002 v5.0q

- URL: `https://ftp-trace.ncbi.nlm.nih.gov/ReferenceSamples/giab/release/AshkenazimTrio/HG002_NA24385_son/v5.0q/`
- Files: `HG002_GRCh38_v5.0q_smvar.vcf.gz` (+ `.tbi`) and `HG002_GRCh38_v5.0q_smvar.benchmark.bed`.
- The VCF lists HG002's validated small variants (SNVs and indels); the BED lists the regions where
  that list is complete. Only variants inside the BED are scored.

**Why v5.0q and not v4.2.1.** NIST lists v4.2.1 as superseded for HG002 by v5.0q, an
assembly-based benchmark built from the T2T-HG002 Q100 v1.1 diploid assembly. It covers more of
the genome, including difficult regions. v5.0q is still labelled a *draft*; following the GIAB
README, it is cited through the T2T Q100 project.

**Why a versioned path.** The pipeline points to `v5.0q/`, never to `latest/`: `latest/` moves
when NIST publishes a new release, which would silently change the results.

**hap.py settings from the GIAB README:** `--engine vcfeval`, `--gender male` (HG002 is male;
hap.py does not infer sex correctly), and GIAB v3.6 stratifications.

**Known issue.** In GIAB's `checksum.md5`, the line for
`HG002_GRCh38_v5.0q_smvar.exclusion_stats.txt` carries trailing garbage characters, so
`md5sum -c` cannot find that file. The script verifies only the lines for the three files it uses,
matched by exact name.

## Reference genome: GRCh38 GIABv3

- URL: `https://ftp-trace.ncbi.nlm.nih.gov/ReferenceSamples/giab/release/references/GRCh38/GRCh38_GIABv3_no_alt_analysis_set_maskedGRC_decoys_MAP2K3_KMT2C_KCNJ18.fasta.gz`
- sha256 (recorded by us; GIAB publishes none):
  `b37cb9a9c0f8716fdb13e2c5c60f08cb8be40de39c3088176f1f62d9e8eeeed8`

**Why this reference.** The truth set's coordinates only mean something on the reference used to
build it. GIAB's own configuration for v5.0q (`defrabb_files/resources.yml`) names this exact file.
Compared with the standard GRCh38 analysis set it:

- has **no alt contigs** (alternative copies of regions that make reads map ambiguously, lowering
  mapping quality and therefore recall);
- **masks false duplications** of GRCh38 with `N` (coordinates unchanged);
- adds **decoys** for a few collapsed duplications.

chr20 is not affected by the GRC exclusion list. Chromosome names (`chr1`…`chrX`, `chrY`) match
the truth VCF.

## Reads: HG002 chr20, Illumina NovaSeq

- URL: `https://storage.googleapis.com/deepvariant/case-study-testdata/HG002.novaseq.pcr-free.35x.dedup.grch38_no_alt.chr20.bam` (+ `.bai`)
- md5 (base64, from the `x-goog-hash` header): `jxpUGjSIA+MEJ1NZrFLaVw==`
- PrecisionFDA Truth Challenge v2 data, PCR-free library, 2x150 bp. The same dataset is used in the
  v5.0q manuscript to evaluate Illumina calls.

The BAM is only a container for the reads. It is converted back to FASTQ and the pipeline realigns
the reads to our reference, so its original alignment (to the standard GRCh38 no-alt set) is
discarded.

**BAM to FASTQ.**

```bash
samtools collate -u -O <bam> | samtools fastq -n -1 R1.fastq.gz -2 R2.fastq.gz -0 /dev/null -s /dev/null -
```

- `collate` groups the two reads of each pair by name. The BAM is sorted by position, so mates can
  be far apart; without this step R1 and R2 would be out of sync and the aligner would pair reads
  that do not belong together.
- Reads whose mate is not in the file are dropped (`-s /dev/null`). Supplementary and secondary
  alignments are skipped by `samtools fastq`.

| Metric (samtools flagstat) | Value |
|---|---|
| Primary reads | 19,256,947 |
| Marked duplicates (not removed) | 1,993,115 (~10 %) |
| Supplementary alignments (excluded) | 210,208 |
| Mate on another chromosome (dropped) | 332,047 (~1.7 %) |
| **Read pairs written** | **9,462,450** |

Duplicates are only *marked* in the source BAM, so they come back as normal reads in the FASTQ and
`MarkDuplicates` in the pipeline has real work to do. Effective depth on chr20 is roughly 40x.

FASTQ checksums (valid for files produced with the pinned samtools image):

| File | sha256 |
|---|---|
| `HG002_chr20_R1.fastq.gz` | `062b01723523de184d3a2d78563429e9df0e781c99c0f1d503fbb1697a11bd3e` |
| `HG002_chr20_R2.fastq.gz` | `102592f715193b104c5657053d5f9c9a25bac097f72448d64f3bc1af094a76ec` |

The script checks content rather than these hashes: same number of reads in R1 and R2 (9,462,450)
and identical read names in the same order.

## Stratifications: GIAB v3.6

- URL: `https://ftp-trace.ncbi.nlm.nih.gov/ReferenceSamples/giab/release/genome-stratifications/v3.6/GRCh38@all/`

Stratifications split the score into genomic contexts, so the results show *where* each caller
fails instead of a single average. Eight were selected:

| ID | Region | Why it matters |
|---|---|---|
| `notinalldifficultregions` | Easy regions | Baseline performance |
| `alldifficultregions` | All difficult regions | Complement of the above |
| `AllHomopolymers_ge7bp_imperfectge11bp_slop5` | Homopolymers (e.g. `AAAAAAAA`) | Main source of indel errors |
| `AllTandemRepeats` | Tandem repeats (e.g. `CACACA`) | Repeat length is hard to resolve |
| `segdups` | Segmental duplications | Reads map to the wrong copy |
| `lowmappabilityall` | Low mappability | Short reads cannot be placed uniquely |
| `gc15_slop50` | GC < 15 % | Lower Illumina coverage |
| `gc85_slop50` | GC > 85 % | Lower Illumina coverage |

`GenomeSpecific` stratifications were left out because they are derived from the older v4.2.1
benchmark.

## Container images

| Tool | Image | Digest |
|---|---|---|
| samtools 1.24 | `quay.io/biocontainers/samtools:1.24--h9dcdb79_1` | `sha256:a130447589651ed09252aa95a5e4f4132942cdb54d835d81a04a9a930d656561` |
| bcftools 1.24 | `quay.io/biocontainers/bcftools:1.24--h118bc1c_4` | `sha256:186c45de3059dbb1837006c27788284c89d17f8e693e7804624b6cf6ca5caca0` |

Images come from BioContainers (built automatically from Bioconda recipes) and are pinned by tag
**and** digest, so the exact same image is used locally, in CI and on AWS.

## CI dataset

A minimal dataset lets GitHub Actions run the whole pipeline in minutes. It is published as a
GitHub Release asset rather than committed, so the repository history stays small.

- URL: `https://github.com/leorosas7777/germline-variant-benchmark/releases/download/testdata-v1/germline-ci-testdata-v1.tar.gz`
- sha256: `6f7f8bc2ae3cc5da2e58f63b9e77eb43633d78a07a1af5854b047ea9e0938791` (39 MB)
- Region: `chr20:10,000,000-11,000,000`

| File | Content |
|---|---|
| `chr20.fa`, `.fai` | Reference, chr20 only (full length, original coordinates) |
| `HG002_ci_R1/R2.fastq.gz` | 130,069 read pairs touching the region (mates outside it are kept) |
| `truth_ci.vcf.gz`, `.tbi` | Truth variants in the region (1,805) |
| `truth_ci.bed` | Confident regions clipped to the region |
| `stratifications/` | The 8 stratifications clipped to the region + `ci-stratifications.tsv` |

**How the region was chosen.** A 1 Mb window with a typical density of truth variants
(1,423 SNVs and 333 indels inside the confident regions), away from the chromosome ends and the
centromere (~26-30 Mb, which has no truth). It contains both easy (90.5 %) and difficult (9.5 %)
sequence, so the CI run also exercises the stratified report. `gc85_slop50` is empty in this
window; hap.py reports it with zero counts.

**Why chr20 in full rather than only the region.** Cutting the reference to 1 Mb would shift all
coordinates, so the truth and every BED would have to be shifted too. Keeping chr20 whole costs a
few minutes of indexing but removes a whole class of silent errors.

**Coordinates.** VCF and region strings are 1-based (`chr20:10000000-11000000`); BED files are
0-based, so the same region is `9999999 11000000` in BED.

**Rebuilding.** `bin/fetch_data.sh build-ci` rebuilds the tarball from the full data. A published
asset is never replaced: a new dataset is released under a new tag (`testdata-v2`, …) and the URL
and checksum in the script are updated.

## Limitations

- v5.0q is a draft benchmark without its own publication yet.
- About 1.7 % of reads (pairs with a mate on another chromosome) are dropped.
- The selection of chr20 reads was done on the standard GRCh38 no-alt set, not on GIABv3; the two
  are nearly identical on chr20, so the effect is expected to be minimal.
- Only chr20 is analysed; results are not directly extrapolated to the whole genome.

## Citations

- GIAB v5.0q: cite the T2T Q100 project — <https://github.com/marbl/hg002>,
  <https://doi.org/10.1101/2025.09.21.677443>
- GIAB stratifications: Dwarshuis et al., *The GIAB genomic stratifications resource for human
  reference genomes*, <https://doi.org/10.1101/2023.10.27.563846>
- Benchmarking best practices: Krusche et al., *Nat Biotechnol* 37, 555–560 (2019),
  <https://doi.org/10.1038/s41587-019-0054-x>
