#!/bin/bash

exitCodeCheck(){

    if [[ $! -ne 0 ]]; then
        echo "shell execute return value is $1 not 0"
        exit "$1"
    else
        echo "shell execute success"
    fi
}