version 1.0

workflow nm_mendevar_and_cc {
    input {
        File assembly
    }

    call get_clonal_complex {
        input: assembly=assembly
    }

    call get_mendevar{
        input: assembly=assembly
    }

    output {
        String clonal_complex = get_clonal_complex.clonal_complex
        String mendevar_bexsero_reactivity = get_mendevar.bexsero
        String mendevar_trumenba_reactivity = get_mendevar.trumenba
    }
}

task get_clonal_complex {
    input {
        File assembly
    }

    command <<<
        url="https://rest.pubmlst.org/db/pubmlst_neisseria_seqdef/schemes/1/sequence"

        (echo -n '{"base64":true,"sequence": "'; base64 ~{assembly}; echo '"}') | \
        curl -s -H "Content-Type: application/json" -X POST ${url} -d @- | \
        jq -r '.fields.clonal_complex' > cc.txt
    >>>

    output {
        String clonal_complex = read_string("cc.txt")
    }

    runtime {
        docker: "devorbitus/ubuntu-bash-jq-curl:latest"
    }
}

task get_mendevar {
    input {
        File assembly
    }

    command <<<
        URL_BAST="https://rest.pubmlst.org/db/pubmlst_neisseria_seqdef/schemes/53/sequence"
        URL_BAST_DESIGNATION="https://rest.pubmlst.org/db/pubmlst_neisseria_seqdef/schemes/53/designations"

        # Send the sequence to the server and save the response to bast.json
        (echo -n '{"base64":true,"sequence": "'; base64 ~{assembly}; echo '"}') | \
        curl -s -H "Content-Type: application/json" -X POST ${URL_BAST} -d @- | \
        jq . > bast.json

        declare -A loci
        # Read the content of bast.json and extract allele_id for each key in 'exact_matches'
        for key in $(jq -r '.exact_matches | keys_unsorted | .[]' bast.json); do
            allele_id=$(jq -r ".exact_matches[\"$key\"][0].allele_id" bast.json)
            loci["${key}"]=$allele_id
        done

        data=("fHbp_peptide" "PorA_VR2" "PorA_VR1" "NHBA_peptide" "NadA_peptide")

        url=""
        for val in "${data[@]}"; do
            if [[ -n "${loci[$val]}" ]]; then  # if the key exists in "al"
                url+='"'$val'":[{"allele":"'"${loci[$val]}"'"}],'

            else
                url+='"'$val'":[{"allele":"'"0"'"}],'    
            fi
        done

        url="${url%?}"

        curl -s -H "Content-Type: application/json" \
        -X POST "${URL_BAST_DESIGNATION}" \
        -d "{\"designations\": { ${url} }}" > bast_type.json

        # Extract Bexsero and Trumenba reactivity
        bexsero=$(jq -r '.fields.MenDeVAR_Bexsero_reactivity' bast_type.json > bexsero.txt)
        trumenba=$(jq -r '.fields.MenDeVAR_Trumenba_reactivity' bast_type.json > trumenba.txt)

    >>>

    output {
        String bexsero = read_string("bexsero.txt")
        String trumenba = read_string("trumenba.txt")
    }

    runtime {
        docker: "devorbitus/ubuntu-bash-jq-curl:latest"
    }
}
