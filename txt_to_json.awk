BEGIN{
    found_service=0
    first_entry=0
    FS=" "
    ORS=""
    printf("%s\n","{")
    printf("\t\"hostname\":\"%s\",\n",HNAME)
    printf("\t\"address\":\"%s\",\n",IPADD)
    printf("\t\"port\":\"%s\",\n",APORT)
}
END{
    printf("\n%s","}")
}
function parseAnyLine(line){
    # split(line,txt_entry,/ = /)
    no_singles=split(line,singles,/ "/)
    for (single_entry in singles){
        sub(/"/,"",singles[single_entry])
        #printf("%s\n",singles[single_entry])
    }
    sub(/"/,"",singles[1])
    for (single_entry in singles){
        no_split=split(singles[single_entry],split_single,/=/)  
        if (no_split>1)
        {
            if (first_entry==1){
                printf("%s\n",",")
            }
            printf("\t\"%s\":\"%s\"",split_single[1],split_single[2])
            found=1
            first_entry=1
        }
    }
    # }
    return     
}
#####
# Main
{
    if ($0 ~ /^"/){
        found_service=found_service+1
        if (found_service>1){
            print "\n awk warning: multiple entries!!! \n" > "/dev/stderr"
        }
        print parseAnyLine($0) 
    }
}
