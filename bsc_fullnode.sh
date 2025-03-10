#!/usr/bin/env bash

# Exit script on error
set -e


basedir=$(cd `dirname $0`; pwd)
workspace=${basedir}
source ${workspace}/.env

stateScheme="hash"
syncmode="full"
gcmode="full"
index=0
extraflags=""

src=${workspace}/.local/bsc/node0
if [ ! -d "$src" ] ;then
	echo "you must startup validator firstly..."
	exit 1
fi

if [ ! -z "$2" ] ;then
	index=$2
fi

if [ ! -z "$3" ] ;then
	syncmode=$3
fi

if [ ! -z "$4" ] ;then
	gcmode=$4
fi

if [ ! -z "$5" ] ;then
	extraflags=$5
fi

node=node$index
dst=${workspace}/.local/bsc/fullnode/${node}
hardforkfile=${workspace}/.local/bsc/hardforkTime.txt

# 打印关键参数
echo "=============== 节点参数 ==============="
echo "节点索引: $index"
echo "同步模式: $syncmode"
echo "GC模式: $gcmode"
echo "节点目录: $dst"
echo "额外参数: $extraflags"

# 获取并打印硬分叉相关参数
rialtoHash=`cat $dst/init.log|grep "database=chaindata"|awk -F"=" '{print $NF}'|awk -F'"' '{print $1}'`
PassedForkTime=`cat ${workspace}/.local/bsc/hardforkTime.txt|grep passedHardforkTime|awk -F" " '{print $NF}'`
LastHardforkTime=$(expr ${PassedForkTime} + ${LAST_FORK_MORE_DELAY})

echo "=============== 硬分叉参数 ==============="
echo "Rialto Hash: ${rialtoHash}"
echo "Passed Fork Time: ${PassedForkTime}"
echo "Last Fork Time: ${LastHardforkTime}"

mkdir -pv $dst/

function init() {
  cp $src/config.toml $dst/ && cp $src/genesis.json $dst/
  ${workspace}/bin/geth init --datadir ${dst} --state.scheme ${stateScheme} ${dst}/genesis.json
}

function start() {
  # 构建启动命令
  cmd="${workspace}/bin/geth --config $dst/config.toml --port $(( 31000 + $index ))  \
  --datadir $dst --rpc.allow-unprotected-txs --allow-insecure-unlock \
  --ws.addr 0.0.0.0 --ws.port 8545 --http.addr 0.0.0.0 --http.port 8545 --http.corsdomain \"*\" \
  --metrics --metrics.addr 0.0.0.0 --metrics.port $(( 6100 + $index )) --metrics.expensive \
  --gcmode $gcmode --syncmode $syncmode --state.scheme ${stateScheme} $extraflags \
  --rpc.batch-request-limit 10000 --rpc.batch-response-max-size 250000000 \
  --rialtohash ${rialtoHash} --override.passedforktime ${PassedForkTime} --override.pascal ${LastHardforkTime} --override.prague ${LastHardforkTime} \
  --override.immutabilitythreshold ${FullImmutabilityThreshold} --override.breatheblockinterval ${BreatheBlockInterval} \
  --override.minforblobrequest ${MinBlocksForBlobRequests} --override.defaultextrareserve ${DefaultExtraReserveForBlobRequests}"

  echo "=============== 启动命令 ==============="
  echo "$cmd"
  echo "======================================="

  # 执行启动命令
  nohup $cmd > $dst/bsc-node.log 2>&1 &
  echo $! > $dst/pid
}

function pruneblock() {
  ${workspace}/bin/geth snapshot prune-block --datadir $dst --datadir.ancient $dst/geth/chaindata/ancient/chain
}

function stop() {
  if [ ! -f "$dst/pid" ]; then
    echo "$dst/pid not exist"
  else
    pid=`cat $dst/pid`
    if ps -p $pid > /dev/null 2>&1; then
      kill $pid
      rm -f $dst/pid
      sleep 5
    else
      echo "Process $pid does not exist"
      rm -f $dst/pid
    fi
  fi
}

function clean() {
  stop
  rm -rf $dst/*
}

CMD=$1
case ${CMD} in
start)
    echo "===== start ===="
    start
    echo "===== end ===="
    ;;
init)
    echo "===== init ===="
    init
    echo "===== end ===="
    ;;
stop)
    echo "===== stop ===="
    stop
    echo "===== end ===="
    ;;
restart)
    echo "===== restart ===="
    stop
    start
    echo "===== end ===="
    ;;
clean)
    echo "===== clean ===="
    clean
    echo "===== end ===="
    ;;
pruneblock)
    echo "===== pruneblock ===="
    stop
    pruneblock
    echo "===== end ===="
    ;;
*)
    echo "Usage: bsc_fullnode.sh start|stop|restart|clean|init nodeIndex syncmode gcmode"
    echo "Examples:"
    echo "  Initialize node:           bsc_fullnode.sh init 1"
    echo "  Full sync + Full node:     bsc_fullnode.sh start 1 full full"
    echo "  Full sync + Archive node:  bsc_fullnode.sh start 1 full archive"
    echo "  Snap sync + Full node:     bsc_fullnode.sh start 1 snap full"
    echo "  Snap sync + Archive node:  bsc_fullnode.sh start 1 snap archive"
    echo ""
    echo "State Scheme Options (--state.scheme):"
    echo "  hash:    使用传统的MPT(Merkle Patricia Trie)状态存储方案，归档节点必须使用此选项"
    echo "  path:    使用路径方案存储状态，可以提供更好的性能，但需要更多磁盘空间"
    echo "  plain:   使用简单的键值对存储状态，占用空间最大但查询最快"
    ;;
esac