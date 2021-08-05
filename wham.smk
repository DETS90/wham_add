configfile: "config.yaml"
SAMPLES=config['samples']
# Set rules to accomplish
ALL_SAMPLES = SAMPLES
### Cleaning and mapping
SAMPLES_BAM = expand("{sample}/bam/{sample}.sorted.bam", sample=SAMPLES)
ALL_BAM = SAMPLES_BAM
ALL_DUP = expand ("{sample}/bam/{sample}.duplicate.bam", sample=SAMPLES)
ALL_DUP_BAI = expand ("{sample}/bam/{sample}.duplicate.bam.bai", sample=SAMPLES)
### wham
ALL_WHAM = expand ("{sample}/wham_out/{sample}.vcf", sample=SAMPLES)
### svs per sample
ALL_SURVIVOR = expand("{sample}/{sample}.vcf",sample=SAMPLES)

rule all:
    input:
    ALL_BAM + ALL_SORT + ALL_BAI  + ALL_DUP + ALL_DUP_BAI +
    ALL_WHAM + ALL_SURVIVOR

## Align to the genome
rule align:
    input:
        r1="files/{sample}_R1.fastq.gz",
        r2="files/{sample}_R2.fastq.gz"
    output: "{sample}/bam/{sample}.unsorted.bam"
    threads: 4
    log: "logs/{sample}.aligned.txt"
    shell:
        "bwa mem -t {threads} {config[idx_FASTA]} {input} 2> {log} | samtools view -Sb > {output}"
#### check briefly length of reads

rule sort_bam:
    input:  rules.align.output
    output: "{sample}/bam/{sample}.sorted.bam"
    log:    "logs/{sample}.sort_bam.txt"
    threads: 4
    shell:
        "samtools sort -m 1G -@ {threads} -O bam -T {output}.tmp {input} > {output} 2> {log}"

rule index_bam:
    input:  rules.sort_bam.output
    output: "{sample}/bam/{sample}.sorted.bam.bai"
    log:    "logs/{sample}.index_bam.txt"
    threads: 4
    shell:
        "samtools index {input} {output} 2> {log}"
## Clean for duplicates

rule remove_duplicates:
    input: "{sample}/bam/{sample}.sorted.bam"
    output:
        bam = "{sample}/bam/{sample}.duplicate.bam",
        dup = temp("{sample}/bam/{sample}.duplicate.txt")
    log : "logs/{sample}.duplicate.txt"
    params:
        a = "true",
        b = "coordinate"
    threads: 4
    shell:
        "picard MarkDuplicates -I {input} -M {output.dup} -O {output.bam} --REMOVE_DUPLICATES {params.a} --ASSUME_SORT_ORDER {params.b}"

rule index_duplicates:
    input:  rules.remove_duplicates.output.bam
    output: "{sample}/bam/{sample}.duplicate.bam.bai"
    log:"logs/{sample}.index_bam.txt"
    threads: 4
    shell:
        "samtools index {input} {output} 2> {log}"

rule_whamm:
    input:"{sample}/bam/{sample}.duplicate.bam"
    output: "{sample}/wham_out/{sample}.vcf"
    log:"logs/{sample}.wham_err.txt"
    shell:
        "whamg -e {config[idx_EXCLUDE]} -a {config[idx_FASTA]} -f {input} | perl filtWhamG.pl | \
        bcftools filter -e 'QUAL==0 && DP<10' > {output}  2> {log}"
# exclude masked regions
## use vcfs generated by sv-callers
#file.txt include callers to use: use delly_out,lumpy_out,whamm_out,manta_out

rule_survivor
    input:"{sample}/files.txt"
    output:"{sample}/{sample}.vcf"
    params:
        use=3
        dist=1000
        type=1
    log:"logs/{sample}.survivor.txt"
    shell:
        "SURVIVOR merge {input} {params.dist} {params.use} {params.type} {output}"

# check final results per sample and merge the full set of SVs within V. dahliae
