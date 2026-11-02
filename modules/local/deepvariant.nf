process DEEPVARIANT {
    tag "${meta.id}"
    container 'google/deepvariant:1.10.0@sha256:962e5a83b1d76aae6990625d47102785f791603f2138aa1fa9aa4fb6a2eecbe6'

    input:
    tuple val(meta), path(bam), path(bai)
    path fasta
    path fai
    val regions

    output:
    tuple val(meta), path("*.deepvariant.vcf.gz"), path("*.deepvariant.vcf.gz.tbi"), emit: vcf

    script:
    def region_arg = regions ? "--regions=${regions}" : ''
    """
    /opt/deepvariant/bin/run_deepvariant \\
        --model_type=WGS \\
        --ref=${fasta} \\
        --reads=${bam} \\
        --output_vcf=${meta.id}.deepvariant.vcf.gz \\
        --num_shards=${task.cpus} \\
        --intermediate_results_dir=dv_tmp \\
        ${region_arg}
    """
}
