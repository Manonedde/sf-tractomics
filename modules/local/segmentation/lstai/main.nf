process SEGMENTATION_LSTAI {
    tag "$meta.id"
    label 'process_high'

    container "jqmcginnis/lst-ai:v2.0.0rc1-cpu"

    // The image bakes in ENTRYPOINT ["lst"] / CMD ["--help"] (it's meant to be run
    // as `docker run jqmcginnis/lst-ai --t1 ... --flair ...`, i.e. the tool itself
    // is the entrypoint). Without this override, Nextflow's own generated shell
    // command gets passed as arguments to `lst` instead of being executed, and the
    // task fails with "the following arguments are required: --t1, --flair,
    // --output". Docker/Podman honour ENTRYPOINT and need it cleared; Singularity/
    // Apptainer do not use it in the first place.
    containerOptions {
        workflow.containerEngine in ['singularity', 'apptainer']
            ? ''
            : '--entrypoint ""'
    }

    input:
        tuple val(meta), path(t1), path(flair)

    output:
        tuple val(meta), path("*_lesion_mask.nii.gz")                   , emit: lesion_mask
        tuple val(meta), path("*_desc-annotated_mask_lesion.nii.gz")    , emit: lesion_mask_annotated, optional: true
        tuple val(meta), path("*_lesion_stats.csv")                     , emit: lesion_stats, optional: true
        tuple val(meta), path("*_lesion_stats_annotated.csv")           , emit: lesion_stats_annotated, optional: true
        path "versions.yml"                                              , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def device = task.ext.device ?: "cpu"
    def stripped = task.ext.stripped ? "--stripped" : ""
    def segment_only = task.ext.segment_only ? "--segment_only" : ""
    def threshold = task.ext.threshold ? "--threshold ${task.ext.threshold}" : ""
    def lesion_threshold = task.ext.lesion_threshold ? "--lesion_threshold ${task.ext.lesion_threshold}" : ""
    def clipping = task.ext.clipping ? "--clipping ${task.ext.clipping}" : ""
    def fast_mode = task.ext.fast_mode ? "--fast-mode" : ""
    def threads = task.ext.single_thread ? 1 : task.cpus

    """
    lst \
        --t1 $t1 \
        --flair $flair \
        --output lst_output \
        --temp lst_temp \
        --device $device \
        --threads $threads \
        $stripped \
        $segment_only \
        $threshold \
        $lesion_threshold \
        $clipping \
        $fast_mode

    mv lst_output/space-flair_seg-lst.nii.gz ${prefix}_lesion_mask.nii.gz
    mv lst_output/lesion_stats.csv ${prefix}_lesion_stats.csv

    if [[ -f lst_output/space-flair_desc-annotated_seg-lst.nii.gz ]]; then
        mv lst_output/space-flair_desc-annotated_seg-lst.nii.gz ${prefix}_desc-annotated_mask_lesion.nii.gz
        mv lst_output/annotated_lesion_stats.csv ${prefix}_lesion_stats_annotated.csv
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        lst-ai: \$(pip show lst-ai 2>/dev/null | sed -n 's/^Version: //p')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    set +e
    function handle_code () {
    local code=\$?
    ignore=( 1 )
    [[ " \${ignore[@]} " =~ " \$code " ]] || exit \$code
    }
    trap 'handle_code' ERR

    lst -h

    touch ${prefix}_lesion_mask.nii.gz
    touch ${prefix}_desc-annotated_mask_lesion.nii.gz
    touch ${prefix}_lesion_stats.csv
    touch ${prefix}_lesion_stats_annotated.csv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        lst-ai: \$(pip show lst-ai 2>/dev/null | sed -n 's/^Version: //p')
    END_VERSIONS
    """
}
