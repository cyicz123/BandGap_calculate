#!/bin/bash
#set -e
function error_handle(){
    stty echo
    #echo "安静模式结束"#
}

function initialize()
{
    shiftNum=0
    for i in $@
    do
        echo $i|[ `sed -n '/^--\?.*\(s\|silent\).*$/p'` ] && isSilence='-s'
        if [ $isSilence ];then
            #echo "安静模式开启"#
            stty -echo
            trap error_handle INT
            trap error_handle TERM
            trap error_handle KILL
            trap error_handle EXIT
        fi
        echo $i|[ `sed -n '/-/p'` ] && ((shiftNum+=1))
        echo $i|[ `sed -n '/^--\?\(h\|help\)$/p'` ] && isHelp='-h'
        echo $i|[ `sed -n '/^--\?\(l\|loop\)$/p'` ] && isLoop='-l'
        echo $i|[ `sed -n '/--\?\(p\|precision\)=\?/p'` ] && precision=`echo $i|grep -P '[1-9][0-9]*' -o`
        echo $i|[ `sed -n '/--\?name=\?/p'` ] && expName=`echo $i| sed 's/--\?name=\(\w\+\).*/\1/g'`
    done    
}

function initializeValue(){
    isSilence=''
    isLoop=''
    isHelp=''
    precision=2
    expName='experiment'
}


#echo "开始"#
initializeValue
initialize $@
shift $shiftNum

if [ $isHelp ];then
    echo -e "-------------------------------------------------------------------"
    echo -e "\n用法：./calculate [参数] [U值 .. ]"
    echo -e "  或：./calculate [参数] U起始值 U递增值 递增次数"
    echo -e "\n"
    echo -e "参数：\n"
    echo -e "-h,--help:\t\t命令帮助 "
    echo -e "-s,--silent:\t\t安静模式"
    echo -e "-l,--loop:\t\t第二种取值模式"
    echo -e "-pn,--precision=n:\t设置精度n，默认为2"
    echo -e "--name=:\t\t设置文件夹名称，默认为experiment"
    echo -e "-------------------------------------------------------------------"
    echo -e "作者：\t\t\tcyicz123"
    echo -e "QQ：\t\t\t602921001"
    echo -e "个人网站：\t\twww.cyicz123.com"
    echo -e "附录：\t\t\t关于计算材料学问题请联系张奕羲QQ:1251221669"
    echo -e "-------------------------------------------------------------------"
    exit 0
fi

echo "精度=$precision,文件夹名:$expName"

nowPath=`pwd`
echo "Path is $nowPath"
test ! -d $nowPath/temp && echo "temp directory doesn't exit." && exit 1
test -d $nowPath/$expName && echo "$expName already exists." && exit 1
mkdir $expName&&echo "mkdir $expName"

if [ $isLoop ];then
    startValue=$1
    increValue=$2
    for ((i = 0; i < $3; i++)); do
        uArr[$i]=`echo "scale=$precision;$startValue+$i*$increValue" | bc`
    done
else
    i=0
    for u in $@;do
        uArr[$i]=$u
        i+=1
    done
fi

echo -e "U值为:\c"
for u in ${uArr[@]};do
    echo -e "$u \c"
done
echo -e "\n"

tempPath=$nowPath/temp
for ((i = 0; i < ${#uArr[@]}; i++)); do
    U=${uArr[i]}
    mkdir $nowPath/$expName/U$U
    echo $tempPath
    cp -r {$tempPath/youhua,$tempPath/static,$tempPath/band} $nowPath/$expName/U$U
    sed -i "s/value/$U/g" $nowPath/$expName/U$U/youhua/INCAR $nowPath/$expName/U$U/static/INCAR $nowPath/$expName/U$U/band/INCAR
    cd $nowPath/$expName/U$U/youhua
    firstIDArr[i]=`qsub vasp.pbs`
done
echo "结构优化进行中..."
while true; do
    flag=0
    for ((i = 0; i < ${#uArr[@]}; i++)); do
        str=`qstat | grep ${firstIDArr[i]} | awk '{print$1}'`
        if [ -z $str ]; then
            flag=1
        else
            flag=0
        fi
    done
    if [ $flag -eq 1 ]; then
        break
    else
        sleep 1m
    fi
done
echo "结构优化已完成"
for ((i = 0; i < ${#uArr[@]}; i++)); do
    U=${uArr[i]}
    cp $nowPath/$expName/U$U/youhua/CONTCAR $nowPath/$expName/U$U/static/POSCAR
    cd $nowPath/$expName/U$U/static
    secondIDArr[i]=`qsub vasp.pbs`
done
echo "静态计算进行中..."
while true; do
    flag=0
    for ((i = 0; i < ${#uArr[@]}; i++)); do
        str=`qstat | grep ${secondIDArr[i]} | awk '{print$1}'`
        if [ -z $str ]; then
            flag=1
        else
            flag=0
        fi
    done
    if [ $flag -eq 1 ]; then
        break
    else
        sleep 1m
    fi
done
echo "静态计算已完成"
expPath=$nowPath/$expName
for ((i=0;i<${#uArr[@]};i++)); do
    U=${uArr[i]}
    cd $expPath/U$U/static
    cp {WAVECAR,POSCAR,POTCAR,CHGCAR} ../band
    cd ../band
    ( echo 3;echo 303; )|vaspkit
    mv KPATH.in KPOINTS
    sanIDArr[$i]=`qsub vasp.pbs`
done
echo "能带计算进行中..."
while true; do
    flag=0
    for ((i = 0; i < ${#uArr[@]}; i++)); do
        str=`qstat | grep ${sanIDArr[i]} | awk '{print$1}'`
        if [ -z $str ]; then
            flag=1
        else
            flag=0
        fi
    done
    if [ $flag -eq 1 ]; then
        break
    else
        sleep 1m
    fi
done
echo "能带计算已完成"
for ((i=0;i<${#uArr[@]};i++)); do
    U=${uArr[i]}
    cd $expPath/U$U/band
    ( echo 21; echo 211 )|vaspkit
    echo "U为$U时的计算结果为：">>$expPath/report.txt
    grep "Band Gap" BAND_GAP>>$expPath/report.txt
done
