export DIR="$( cd "$( dirname "$0" )" && pwd )"
export CDIR=$DIR/config
export BDIR=$DIR/build
export FABRIC_CFG_PATH=${PWD}/configtx

function networkUp() {
    mkdir -p $BDIR

    docker run --rm --name fabric-tools -v $CDIR/:/tmp -w /tmp hyperledger/fabric-tools:2.2 cryptogen generate --config=/tmp/crypto-config.yaml --output="crypto-config"
    sudo mv $CDIR/crypto-config $BDIR/crypto-config

    docker run --rm --name fabric-tools \
        -v $DIR/configtx:/tmp/configtx \
        -v $BDIR/crypto-config:/tmp/crypto-config \
        -e FABRIC_CFG_PATH='/tmp/configtx' \
        -w /tmp/configtx \
        hyperledger/fabric-tools:2.2 \
        configtxgen -profile systemChannel \
        -channelID system-channel -outputBlock ./genesis.block
    sudo mv $DIR/configtx/genesis.block $BDIR/

    docker-compose -f ./docker-compose/docker-compose-islab.yaml -f ./docker-compose/docker-compose-couch.yaml -f ./docker-compose/docker-compose-ca.yaml up -d 2>&1
}

function networkDown() {
    docker-compose -f ./docker-compose/docker-compose-islab.yaml -f ./docker-compose/docker-compose-couch.yaml down --volumes --remove-orphans
}

function createChannel() {
    orgName=$1
    channelName=$2
    channel=${channelName}-channel
    channelProfile=${channelName}Channel

    docker run --rm --name fabric-tools \
        -v $DIR/configtx:/tmp/configtx \
        -v $BDIR/crypto-config:/tmp/crypto-config \
        -e FABRIC_CFG_PATH='/tmp/configtx' \
        -w /tmp/configtx \
        hyperledger/fabric-tools:2.2 \
        configtxgen -profile $channelProfile \
        -channelID $channel -outputCreateChannelTx ./${channel}.tx
    mv $DIR/configtx/${channel}.tx $BDIR/

    PEER_TLS_PATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/${orgName}.islab.re.kr/peers/peer0.${orgName}.islab.re.kr/tls
    CORE_MSPCONFIG_PATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/${orgName}.islab.re.kr/users/Admin@${orgName}.islab.re.kr/msp
    echo $CORE_MSPCONFIG_PATH
    PEER_TLS_CERT_FILE=${PEER_TLS_PATH}/server.crt
    PEER_TLS_KEY_FILE=${PEER_TLS_PATH}/server.key
    PEER_TLS_CA_CERT=${PEER_TLS_PATH}/ca.crt
    ORDERER_CA_CERT=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/ordererOrganizations/islab.re.kr/orderers/orderer0.islab.re.kr/tls/ca.crt

    docker exec -i -t \
        -e FABRIC_CFG_PATH=/opt/gopath/src/github.com/hyperledger/fabric/config \
        -e CORE_PEER_ID=peer0.${orgName}.islab.re.kr:7051 \
        -e CORE_PEER_ADDRESS=peer0.${orgName}.islab.re.kr:7051 \
        -e CORE_PEER_LISTENADDRESS=0.0.0.0:7051 \
        -e CORE_PEER_MSPCONFIGPATH=$CORE_MSPCONFIG_PATH \
        -e CORE_PEER_LOCALMSPID=${orgName}MSP \
        -e CORE_PEER_TLS_ENABLED=true \
        -e CORE_PEER_TLS_CERT_FILE=$PEER_TLS_CERT_FILE \
        -e CORE_PEER_TLS_KEY_FILE=$PEER_TLS_KEY_FILE \
        -e CORE_PEER_TLS_ROOTCERT_FILE=$PEER_TLS_CA_CERT \
        cli peer channel create \
            -c ${channel} \
            -f /opt/gopath/src/github.com/hyperledger/fabric/peer/${channel}.tx \
            --outputBlock /opt/gopath/src/github.com/hyperledger/fabric/peer/${channel}.block \
            -o orderer0.islab.re.kr:7050 --tls \
            --ordererTLSHostnameOverride orderer0.islab.re.kr \
            --cafile $ORDERER_CA_CERT


#    docker exec -i -t \
#         -e FABRIC_CFG_PATH=/opt/gopath/src/github.com/hyperledger/fabric/config \
#         -e CORE_PEER_ID=peer0.${orgName}.islab.re.kr:7051 \
#         -e CORE_PEER_ADDRESS=peer0.${orgName}.islab.re.kr:7051 \
#         -e CORE_PEER_LISTENADDRESS=0.0.0.0:7051 \
#         -e CORE_PEER_MSPCONFIGPATH=$CORE_MSPCONFIG_PATH \
#         -e CORE_PEER_LOCALMSPID=${orgName}MSP \
#         -e CORE_PEER_TLS_ENABLED=true \
#         -e CORE_PEER_TLS_CERT_FILE=$PEER_TLS_CERT_FILE \
#         -e CORE_PEER_TLS_KEY_FILE=$PEER_TLS_KEY_FILE \
#         -e CORE_PEER_TLS_ROOTCERT_FILE=$PEER_TLS_CA_CERT \
#         cli peer channel update \
#             -o orderer0.islab.re.kr:7050 \
#             --ordererTLSHostnameOverride orderer0.islab.re.kr \
#             -c ${channel} \
#             --tls \
#             --cafile $ORDERER_CA_CERT \
#             -f ${orgName}MSPanchors.tx
}

function joinChannel() {

    orgName=$1
    channelName=$2
    channel=${channelName}-channel
    channelProfile=${channelName}Channel

    PEER_TLS_PATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/${orgName}.islab.re.kr/peers/peer0.${orgName}.islab.re.kr/tls
    CORE_MSPCONFIG_PATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/${orgName}.islab.re.kr/users/Admin@${orgName}.islab.re.kr/msp
    echo $CORE_MSPCONFIG_PATH
    PEER_TLS_CERT_FILE=${PEER_TLS_PATH}/server.crt
    PEER_TLS_KEY_FILE=${PEER_TLS_PATH}/server.key
    PEER_TLS_CA_CERT=${PEER_TLS_PATH}/ca.crt
    ORDERER_CA_CERT=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/ordererOrganizations/islab.re.kr/orderers/orderer0.islab.re.kr/tls/ca.crt

    docker exec -i -t \
        -e FABRIC_CFG_PATH=/opt/gopath/src/github.com/hyperledger/fabric/config \
        -e CORE_PEER_ID=peer0.${orgName}.islab.re.kr:7051 \
        -e CORE_PEER_ADDRESS=peer0.${orgName}.islab.re.kr:7051 \
        -e CORE_PEER_LISTENADDRESS=0.0.0.0:7051 \
        -e CORE_PEER_MSPCONFIGPATH=$CORE_MSPCONFIG_PATH \
        -e CORE_PEER_LOCALMSPID=${orgName}MSP \
        -e CORE_PEER_TLS_ENABLED=true \
        -e CORE_PEER_TLS_CERT_FILE=$PEER_TLS_CERT_FILE \
        -e CORE_PEER_TLS_KEY_FILE=$PEER_TLS_KEY_FILE \
        -e CORE_PEER_TLS_ROOTCERT_FILE=$PEER_TLS_CA_CERT \
        cli peer channel join \
            -b /opt/gopath/src/github.com/hyperledger/fabric/peer/${channel}.block

}

function deployCC() {

    CC_NAME=$1
    CC_VERSION=$2
    SEQUENCE=$3

    docker exec -i -t \
        cli peer lifecycle chaincode package \
            ${CC_NAME}.tar.gz \
            --path /opt/gopath/src/github.com/hyperledger/fabric/chaincode/go \
            --lang golang \
            --label ${CC_NAME}_${CC_VERSION}

    if [ ! -d "chaincode/go/vendor" ] ; then
        cd ./chaincode/go
        go mod vendor
        cd ../..
    fi


    installChaincode ai $CC_NAME
    installChaincode blockchain $CC_NAME
    installChaincode security $CC_NAME

    queryinstalled ai
    queryinstalled blockchain
    queryinstalled security

    approveForMyOrg ai rsh-channel $CC_NAME $CC_VERSION $SEQUENCE
    approveForMyOrg blockchain rsh-channel $CC_NAME $CC_VERSION $SEQUENCE
    approveForMyOrg security rsh-channel $CC_NAME $CC_VERSION $SEQUENCE

    approveForMyOrg ai dev-channel $CC_NAME $CC_VERSION $SEQUENCE
    approveForMyOrg blockchain dev-channel $CC_NAME $CC_VERSION $SEQUENCE
    approveForMyOrg security dev-channel $CC_NAME $CC_VERSION $SEQUENCE

    commitChaincode blockchain rsh-channel $CC_NAME $CC_VERSION $SEQUENCE
    commitChaincode blockchain dev-channel $CC_NAME $CC_VERSION $SEQUENCE

    queryCommitted ai rsh-channel $CC_NAME
    queryCommitted blockchain rsh-channel $CC_NAME
    queryCommitted security rsh-channel $CC_NAME

    queryCommitted ai dev-channel $CC_NAME
    queryCommitted blockchain dev-channel $CC_NAME
    queryCommitted security dev-channel $CC_NAME

}

function installChaincode() {

    orgName=$1
    CC_NAME=$2

    PEER_TLS_PATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/${orgName}.islab.re.kr/peers/peer0.${orgName}.islab.re.kr/tls
    CORE_MSPCONFIG_PATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/${orgName}.islab.re.kr/users/Admin@${orgName}.islab.re.kr/msp
    PEER_TLS_CERT_FILE=${PEER_TLS_PATH}/server.crt
    PEER_TLS_KEY_FILE=${PEER_TLS_PATH}/server.key
    PEER_TLS_CA_CERT=${PEER_TLS_PATH}/ca.crt
    ORDERER_CA_CERT=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/ordererOrganizations/islab.re.kr/orderers/orderer0.islab.re.kr/tls/ca.crt

    PEER_TLS_CA_CERT=${PEER_TLS_PATH}/ca.crt
    CORE_MSPCONFIG_PATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/${orgName}.islab.re.kr/users/Admin@${orgName}.islab.re.kr/msp


    docker exec -i -t \
        -e FABRIC_CFG_PATH=/opt/gopath/src/github.com/hyperledger/fabric/config \
        -e CORE_PEER_LOCALMSPID=${orgName}MSP \
        -e CORE_PEER_TLS_ROOTCERT_FILE=$PEER_TLS_CA_CERT \
        -e CORE_PEER_MSPCONFIGPATH=$CORE_MSPCONFIG_PATH \
        -e CORE_PEER_TLS_ENABLED=true \
        -e CORE_PEER_LISTENADDRESS=0.0.0.0:7051 \
        -e CORE_PEER_ID=peer0.${orgName}.islab.re.kr:7051 \
        -e CORE_PEER_ADDRESS=peer0.${orgName}.islab.re.kr:7051 \
        -e CORE_PEER_TLS_CERT_FILE=$PEER_TLS_CERT_FILE \
        -e CORE_PEER_TLS_KEY_FILE=$PEER_TLS_KEY_FILE \
        cli peer lifecycle chaincode install ${CC_NAME}.tar.gz \
            --peerAddresses peer0.${orgName}.islab.re.kr:7051 \
            --tlsRootCertFiles ${PEER_TLS_CA_CERT}
}

function queryinstalled() {

    orgName=$1

    PEER_TLS_PATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/${orgName}.islab.re.kr/peers/peer0.${orgName}.islab.re.kr/tls
    CORE_MSPCONFIG_PATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/${orgName}.islab.re.kr/users/Admin@${orgName}.islab.re.kr/msp
    PEER_TLS_CERT_FILE=${PEER_TLS_PATH}/server.crt
    PEER_TLS_KEY_FILE=${PEER_TLS_PATH}/server.key
    PEER_TLS_CA_CERT=${PEER_TLS_PATH}/ca.crt
    ORDERER_CA_CERT=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/ordererOrganizations/islab.re.kr/orderers/orderer0.islab.re.kr/tls/ca.crt

    PEER_TLS_CA_CERT=${PEER_TLS_PATH}/ca.crt
    CORE_MSPCONFIG_PATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/${orgName}.islab.re.kr/users/Admin@${orgName}.islab.re.kr/msp

    docker exec -i -t \
        -e FABRIC_CFG_PATH=/opt/gopath/src/github.com/hyperledger/fabric/config \
        -e CORE_PEER_LOCALMSPID=${orgName}MSP \
        -e CORE_PEER_TLS_ROOTCERT_FILE=$PEER_TLS_CA_CERT \
        -e CORE_PEER_MSPCONFIGPATH=$CORE_MSPCONFIG_PATH \
        -e CORE_PEER_TLS_ENABLED=true \
        -e CORE_PEER_LISTENADDRESS=0.0.0.0:7051 \
        -e CORE_PEER_ID=peer0.${orgName}.islab.re.kr:7051 \
        -e CORE_PEER_ADDRESS=peer0.${orgName}.islab.re.kr:7051 \
        -e CORE_PEER_TLS_CERT_FILE=$PEER_TLS_CERT_FILE \
        -e CORE_PEER_TLS_KEY_FILE=$PEER_TLS_KEY_FILE \
        cli peer lifecycle chaincode queryinstalled \
            --peerAddresses peer0.${orgName}.islab.re.kr:7051 \
            --tlsRootCertFiles ${PEER_TLS_CA_CERT}
}

function approveForMyOrg(){
    orgName=$1
    CHANNEL_NAME=$2
    CC_NAME=$3
    CC_VERSION=$4
    SEQUENCE=$5

    PEER_TLS_PATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/${orgName}.islab.re.kr/peers/peer0.${orgName}.islab.re.kr/tls
    CORE_MSPCONFIG_PATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/${orgName}.islab.re.kr/users/Admin@${orgName}.islab.re.kr/msp
    PEER_TLS_CERT_FILE=${PEER_TLS_PATH}/server.crt
    PEER_TLS_KEY_FILE=${PEER_TLS_PATH}/server.key
    PEER_TLS_CA_CERT=${PEER_TLS_PATH}/ca.crt
    ORDERER_CA_CERT=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/ordererOrganizations/islab.re.kr/orderers/orderer0.islab.re.kr/tls/ca.crt

    PEER_TLS_CA_CERT=${PEER_TLS_PATH}/ca.crt
    CORE_MSPCONFIG_PATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/${orgName}.islab.re.kr/users/Admin@${orgName}.islab.re.kr/msp

    docker exec -i -t \
        -e FABRIC_CFG_PATH=/opt/gopath/src/github.com/hyperledger/fabric/config \
        -e CORE_PEER_LOCALMSPID=${orgName}MSP \
        -e CORE_PEER_TLS_ROOTCERT_FILE=$PEER_TLS_CA_CERT \
        -e CORE_PEER_MSPCONFIGPATH=$CORE_MSPCONFIG_PATH \
        -e CORE_PEER_TLS_ENABLED=true \
        -e CORE_PEER_LISTENADDRESS=0.0.0.0:7051 \
        -e CORE_PEER_ID=peer0.${orgName}.islab.re.kr:7051 \
        -e CORE_PEER_ADDRESS=peer0.${orgName}.islab.re.kr:7051 \
        -e CORE_PEER_TLS_CERT_FILE=$PEER_TLS_CERT_FILE \
        -e CORE_PEER_TLS_KEY_FILE=$PEER_TLS_KEY_FILE \
        cli peer lifecycle chaincode approveformyorg \
            -o orderer0.islab.re.kr:7050 --tls \
            --cafile $ORDERER_CA_CERT \
            --channelID $CHANNEL_NAME \
            --name $CC_NAME \
            --version $CC_VERSION \
            --sequence $SEQUENCE \
            --waitForEvent \
            --signature-policy "OR ('aiMSP.peer', 'blockchainMSP.peer','securityMSP.peer')" \
            --package-id ${CC_NAME}_${CC_VERSION}:937ab13b4a73fa06849b23ca651f0707e6cb5e14f997e11e013157db016b154a

    # commit check
    checkCommitReadiness ai $CHANNEL_NAME $CC_NAME $CC_VERSION $SEQUENCE
    checkCommitReadiness blockchain $CHANNEL_NAME $CC_NAME $CC_VERSION $SEQUENCE
    checkCommitReadiness security $CHANNEL_NAME $CC_NAME $CC_VERSION $SEQUENCE
}

function checkCommitReadiness() {

    orgName=$1
    CHANNEL_NAME=$2
    CC_NAME=$3
    CC_VERSION=$4
    SEQUENCE=$5

    PEER_TLS_PATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/${orgName}.islab.re.kr/peers/peer0.${orgName}.islab.re.kr/tls
    CORE_MSPCONFIG_PATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/${orgName}.islab.re.kr/users/Admin@${orgName}.islab.re.kr/msp
    PEER_TLS_CERT_FILE=${PEER_TLS_PATH}/server.crt
    PEER_TLS_KEY_FILE=${PEER_TLS_PATH}/server.key
    PEER_TLS_CA_CERT=${PEER_TLS_PATH}/ca.crt
    ORDERER_CA_CERT=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/ordererOrganizations/islab.re.kr/orderers/orderer0.islab.re.kr/tls/ca.crt

    PEER_TLS_CA_CERT=${PEER_TLS_PATH}/ca.crt
    CORE_MSPCONFIG_PATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/${orgName}.islab.re.kr/users/Admin@${orgName}.islab.re.kr/msp


    docker exec -i -t \
        -e FABRIC_CFG_PATH=/opt/gopath/src/github.com/hyperledger/fabric/config \
        -e CORE_PEER_LOCALMSPID=${orgName}MSP \
        -e CORE_PEER_TLS_ROOTCERT_FILE=$PEER_TLS_CA_CERT \
        -e CORE_PEER_MSPCONFIGPATH=$CORE_MSPCONFIG_PATH \
        -e CORE_PEER_TLS_ENABLED=true \
        -e CORE_PEER_LISTENADDRESS=0.0.0.0:7051 \
        -e CORE_PEER_ID=peer0.${orgName}.islab.re.kr:7051 \
        -e CORE_PEER_ADDRESS=peer0.${orgName}.islab.re.kr:7051 \
        -e CORE_PEER_TLS_CERT_FILE=$PEER_TLS_CERT_FILE \
        -e CORE_PEER_TLS_KEY_FILE=$PEER_TLS_KEY_FILE \
        cli peer lifecycle chaincode checkcommitreadiness \
            --channelID $CHANNEL_NAME \
            --name $CC_NAME \
            --version $CC_VERSION \
            --sequence $SEQUENCE \
            --signature-policy "OR ('aiMSP.peer', 'blockchainMSP.peer','securityMSP.peer')" \
            --output json
}

function commitChaincode() {
    orgName=$1
    CHANNEL_NAME=$2
    CC_NAME=$3
    CC_VERSION=$4
    SEQUENCE=$5

    PEER_TLS_PATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/${orgName}.islab.re.kr/peers/peer0.${orgName}.islab.re.kr/tls
    CORE_MSPCONFIG_PATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/${orgName}.islab.re.kr/users/Admin@${orgName}.islab.re.kr/msp
    PEER_TLS_CERT_FILE=${PEER_TLS_PATH}/server.crt
    PEER_TLS_KEY_FILE=${PEER_TLS_PATH}/server.key
    PEER_TLS_CA_CERT=${PEER_TLS_PATH}/ca.crt
    ORDERER_CA_CERT=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/ordererOrganizations/islab.re.kr/orderers/orderer0.islab.re.kr/tls/ca.crt

    PEER_TLS_CA_CERT=${PEER_TLS_PATH}/ca.crt
    CORE_MSPCONFIG_PATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/${orgName}.islab.re.kr/users/Admin@${orgName}.islab.re.kr/msp


    docker exec -i -t \
        -e FABRIC_CFG_PATH=/opt/gopath/src/github.com/hyperledger/fabric/config \
        -e CORE_PEER_LOCALMSPID=${orgName}MSP \
        -e CORE_PEER_TLS_ROOTCERT_FILE=$PEER_TLS_CA_CERT \
        -e CORE_PEER_MSPCONFIGPATH=$CORE_MSPCONFIG_PATH \
        -e CORE_PEER_TLS_ENABLED=true \
        -e CORE_PEER_LISTENADDRESS=0.0.0.0:7051 \
        -e CORE_PEER_ID=peer0.${orgName}.islab.re.kr:7051 \
        -e CORE_PEER_ADDRESS=peer0.${orgName}.islab.re.kr:7051 \
        -e CORE_PEER_TLS_CERT_FILE=$PEER_TLS_CERT_FILE \
        -e CORE_PEER_TLS_KEY_FILE=$PEER_TLS_KEY_FILE \
        cli peer lifecycle chaincode commit \
            -o orderer0.islab.re.kr:7050 \
            --tls \
            --cafile $ORDERER_CA_CERT \
            --channelID $CHANNEL_NAME \
            --name $CC_NAME \
            --peerAddresses peer0.security.islab.re.kr:7051 \
            --tlsRootCertFiles /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/security.islab.re.kr/peers/peer0.security.islab.re.kr/tls/ca.crt \
            --peerAddresses peer0.ai.islab.re.kr:7051 \
            --tlsRootCertFiles /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/ai.islab.re.kr/peers/peer0.ai.islab.re.kr/tls/ca.crt \
            --peerAddresses peer0.blockchain.islab.re.kr:7051 \
            --tlsRootCertFiles /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/blockchain.islab.re.kr/peers/peer0.blockchain.islab.re.kr/tls/ca.crt \
            --version $CC_VERSION \
            --sequence $SEQUENCE \
            --signature-policy "OR ('aiMSP.peer', 'blockchainMSP.peer','securityMSP.peer')"

}

function queryCommitted() {
    orgName=$1
    CHANNEL_NAME=$2
    CC_NAME=$3

    PEER_TLS_PATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/${orgName}.islab.re.kr/peers/peer0.${orgName}.islab.re.kr/tls
    CORE_MSPCONFIG_PATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/${orgName}.islab.re.kr/users/Admin@${orgName}.islab.re.kr/msp
    PEER_TLS_CERT_FILE=${PEER_TLS_PATH}/server.crt
    PEER_TLS_KEY_FILE=${PEER_TLS_PATH}/server.key
    PEER_TLS_CA_CERT=${PEER_TLS_PATH}/ca.crt

    docker exec -i -t \
        -e FABRIC_CFG_PATH=/opt/gopath/src/github.com/hyperledger/fabric/config \
        -e CORE_PEER_LOCALMSPID=${orgName}MSP \
        -e CORE_PEER_TLS_ROOTCERT_FILE=$PEER_TLS_CA_CERT \
        -e CORE_PEER_MSPCONFIGPATH=$CORE_MSPCONFIG_PATH \
        -e CORE_PEER_TLS_ENABLED=true \
        -e CORE_PEER_LISTENADDRESS=0.0.0.0:7051 \
        -e CORE_PEER_ID=peer0.${orgName}.islab.re.kr:7051 \
        -e CORE_PEER_ADDRESS=peer0.${orgName}.islab.re.kr:7051 \
        -e CORE_PEER_TLS_CERT_FILE=$PEER_TLS_CERT_FILE \
        -e CORE_PEER_TLS_KEY_FILE=$PEER_TLS_KEY_FILE \
        cli peer lifecycle chaincode querycommitted \
            --channelID $CHANNEL_NAME \
            --name $CC_NAME \
            --output json
}

function chaincodeInvoke() {

    orgName=$1
    CHANNEL_NAME=$2
    CC_NAME=$3
    QUERY_TYPE=$4
    PARAMS_ID=$5
    PARAMS_COLOR=$6
    PARMAS_SIZE=$7
    PARAMS_OWNER=$8
    PARAMS_VALUE=$9
    PARAMS_NEW_OWNER=$10

    PEER_TLS_PATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/${orgName}.islab.re.kr/peers/peer0.${orgName}.islab.re.kr/tls
    CORE_MSPCONFIG_PATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/${orgName}.islab.re.kr/users/Admin@${orgName}.islab.re.kr/msp
    PEER_TLS_CERT_FILE=${PEER_TLS_PATH}/server.crt
    PEER_TLS_KEY_FILE=${PEER_TLS_PATH}/server.key
    PEER_TLS_CA_CERT=${PEER_TLS_PATH}/ca.crt
    ORDERER_CA_CERT=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/ordererOrganizations/islab.re.kr/orderers/orderer0.islab.re.kr/tls/ca.crt

    AI_PEER_TLS_CA_CERT=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/ai.islab.re.kr/peers/peer0.ai.islab.re.kr/tls/ca.crt
    BLOCKCHAIN_PEER_TLS_CA_CERT=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/blockchain.islab.re.kr/peers/peer0.blockchain.islab.re.kr/tls/ca.crt
    SECURITY_PEER_TLS_CA_CERT=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/security.islab.re.kr/peers/peer0.security.islab.re.kr/tls/ca.crt

    query={'"'Args'"':['"'$QUERY_TYPE'"'
    if [ "$QUERY_TYPE" == "CreateAsset" ]; then
        query+=,'"'$PARAMS_ID'"','"'$PARAMS_COLOR'"','"'$PARMAS_SIZE'"','"'$PARAMS_OWNER'"','"'$PARAMS_VALUE'"']}
    elif [ "$QUERY_TYPE" == "UpdateAsset" ]; then
        query+=,'"'$PARAMS_ID'"','"'$PARAMS_COLOR'"','"'$PARMAS_SIZE'"','"'$PARAMS_OWNER'"','"'$PARAMS_VALUE'"']}
    elif [ "$QUERY_TYPE" == "DeleteAsset" ]; then
        query+=,'"'$PARAMS_ID'"']}
    elif [ "$QUERY_TYPE" == "TransferAsset" ]; then
        query+=,'"'$PARAMS_ID'"','"'$PARAMS_NEW_OWNER'"']}
    elif [ "$QUERY_TYPE" == "InitLedger" ]; then
        query+=]}
    else
        echo "$QUERY_TYPE is invalid type."
        echo " "
        printHelp $MODE
        exit 0
    fi

    docker exec -i -t \
        -e FABRIC_CFG_PATH=/opt/gopath/src/github.com/hyperledger/fabric/config \
        -e CORE_PEER_LOCALMSPID=${orgName}MSP \
        -e CORE_PEER_TLS_ROOTCERT_FILE=$PEER_TLS_CA_CERT \
        -e CORE_PEER_MSPCONFIGPATH=$CORE_MSPCONFIG_PATH \
        -e CORE_PEER_TLS_ENABLED=true \
        -e CORE_PEER_GOSSIP_USELEADERELECTION=true \
        -e CORE_PEER_LISTENADDRESS=0.0.0.0:7051 \
        -e CORE_PEER_ID=peer0.${orgName}.islab.re.kr:7051 \
        -e CORE_PEER_ADDRESS=peer0.${orgName}.islab.re.kr:7051 \
        -e CORE_PEER_TLS_CERT_FILE=$PEER_TLS_CERT_FILE \
        -e CORE_PEER_TLS_KEY_FILE=$PEER_TLS_KEY_FILE \
        cli peer chaincode invoke \
            -o orderer0.islab.re.kr:7050 \
            --tls \
            -C $CHANNEL_NAME \
            -n $CC_NAME \
            --cafile $ORDERER_CA_CERT \
            --peerAddresses peer0.security.islab.re.kr:7051 \
            --tlsRootCertFiles $SECURITY_PEER_TLS_CA_CERT \
            --peerAddresses peer0.ai.islab.re.kr:7051 \
            --tlsRootCertFiles $AI_PEER_TLS_CA_CERT \
            --peerAddresses peer0.blockchain.islab.re.kr:7051 \
            --tlsRootCertFiles $BLOCKCHAIN_PEER_TLS_CA_CERT \
            -c $query
            # '{"Args":["CreateAsset","asset1","blue","1","hyeonhui","10000"]}'
}

function chaincodeQuery() {
    orgName=blockchain
    CHANNEL_NAME=$1
    CC_NAME=$2
    QUERY_TYPE=$3
    PARAMS_ID=$4

    PEER_TLS_PATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/${orgName}.islab.re.kr/peers/peer0.${orgName}.islab.re.kr/tls
    CORE_MSPCONFIG_PATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/${orgName}.islab.re.kr/users/Admin@${orgName}.islab.re.kr/msp
    PEER_TLS_CERT_FILE=${PEER_TLS_PATH}/server.crt
    PEER_TLS_KEY_FILE=${PEER_TLS_PATH}/server.key
    PEER_TLS_CA_CERT=${PEER_TLS_PATH}/ca.crt
    ORDERER_CA_CERT=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/ordererOrganizations/islab.re.kr/orderers/orderer0.islab.re.kr/tls/ca.crt

    query={'"'Args'"':['"'$QUERY_TYPE'"'
    if [ "$QUERY_TYPE" == "AssetExists" ] || [ "$QUERY_TYPE" == "ReadAsset" ]; then
        query+=,'"'$PARAMS_ID'"']}
    elif [ "$QUERY_TYPE" == "GetAllAssets" ]; then
        query+=]}
    else
        echo "$QUERY_TYPE is invalid type."
        echo " "
        printHelp $MODE
        exit 0
    fi
    docker exec -i -t \
        -e FABRIC_CFG_PATH=/opt/gopath/src/github.com/hyperledger/fabric/config \
        -e CORE_PEER_LOCALMSPID=${orgName}MSP \
        -e CORE_PEER_TLS_ROOTCERT_FILE=$PEER_TLS_CA_CERT \
        -e CORE_PEER_MSPCONFIGPATH=$CORE_MSPCONFIG_PATH \
        -e CORE_PEER_TLS_ENABLED=true \
        -e CORE_PEER_GOSSIP_USELEADERELECTION=true \
        -e CORE_PEER_LISTENADDRESS=0.0.0.0:7051 \
        -e CORE_PEER_ID=peer0.${orgName}.islab.re.kr:7051 \
        -e CORE_PEER_ADDRESS=peer0.${orgName}.islab.re.kr:7051 \
        -e CORE_PEER_TLS_CERT_FILE=$PEER_TLS_CERT_FILE \
        -e CORE_PEER_TLS_KEY_FILE=$PEER_TLS_KEY_FILE \
        cli peer chaincode query \
            -C $CHANNEL_NAME \
            -n $CC_NAME \
            -c $query
}

function printHelp() {
    mode=$1
    if [ "$mode" == 'invokeCC' ]; then
        echo "Please enter the valid type"
        echo "Types are InitLedger, CreateAsset, UpdateAsset, DeleteAsset, and TransferAsset."
        echo " "
        echo "InitLedger  -   This is the function to create 6 initial accounts."
        echo "This requires no additional parameters."
        echo " "
        echo "CreateAsset  -   This is a function to add new account information."
        echo "There are 5 types of parameters.  id, color, size, owner, value "
        echo "example) -id asset1 -color blue -size 5 -owner hyeonhui -value 1000"
        echo " "
        echo "UpdateAsset  -   This is a function to edit the information of an existing account."
        echo "There are 5 types of parameters.  id, color, size, owner, value "
        echo "example) -id asset1 -color blue -size 5 -owner hyeonhui -value 1000"
        echo " "
        echo "DeleteAsset  -   This function deletes the information of an account that already exists."
        echo "There are 1 types of parameters.  id"
        echo "example) -id asset1"
        echo " "
        echo "TransferAsset  -   This is a function to change the owner of the account."
        echo "There are 2 types of parameters.  id, changedOwner"
        echo "example) -id asset1 -changedOwner HyeonHee"
    elif [ "$mode" == "queryCC" ]; then
        echo "Please enter the valid type"
        echo "Types are ReadAsset, AssetExists and GetAllAssets"
        echo " "
        echo "ReadAsset  -   This is function to searches the stored account information using the account ID."
        echo "There are 1 types of parameters.  id"
        echo "example) -id asset1"
        echo " "
        echo "AssetExists  -   This is a function to check whether the account with the ID exists by using the account ID."
        echo "There are 1 types of parameters.  id"
        echo "example) -id asset1"
        echo " "
        echo "GetAllAssets  -   TThis is a function to search the information of all accounts stored in world state"
        echo "This requires no additional parameters"
    else
        echo "all | up | down | clean | createChannel | deployCC | invokeCC | queryCC"
        echo " "
        echo "-------------------all-------------------"
        echo "Network down function and network operation, Performs all functions of the channel and chaincode functions. "
        echo " "
        echo "-------------------up-------------------"
        echo "Run the network on docker"
        echo " "
        echo "------------------down------------------"
        echo "Shut down a running network"
        echo " "
        echo "------------------clean------------------"
        echo "Close the running network and delete the contents of the build folder."
        echo " "
        echo "---------------createChannel---------------"
        echo "Create a channel and join it to the channel."
        echo " "
        echo "-----------------deployCC-----------------"
        echo "Install and test chaincode."
        echo " "
        echo "-----------------invokeCC-----------------"
        echo "Chaincode invoke, it need to type"
        echo " "
        echo "-----------------queryCC------------------"
        echo "Chaincode Query, it need to type"
    fi
}

QUERY_TYPE=""
PARAMS_ID=""
PARAMS_COLOR=""
PARMAS_SIZE=""
PARAMS_OWNER=""
PARAMS_NEW_OWNER=""
PARAMS_VALUE=""

if [[ $# -lt 1 ]] ; then
    printHelp
    exit 0
else
    MODE=$1
    shift
fi

while [[ $# -ge 1 ]] ; do
    key="$1"
    case $key in
    -h )
        printHelp $MODE
        exit 0
        ;;
    -type )
        QUERY_TYPE="$2"
        shift
        ;;
    -id )
        PARAMS_ID="$2"
        shift
        ;;
    -color )
        PARAMS_COLOR="$2"
        shift
        ;;
    -size )
        PARMAS_SIZE="$2"
        shift
        ;;
    -owner )
        PARAMS_OWNER="$2"
        shift
        ;;
    -value )
        PARAMS_VALUE="$2"
        shift
        ;;
    -changedOwner )
        PARAMS_NEW_OWNER="$2"
        shift
        ;;
    esac
    shift
done


if [ "$MODE" == "all" ]; then
    networkDown
    sudo rm -Rf $BDIR
    networkUp
    createChannel ai rsh
    joinChannel ai rsh
    joinChannel blockchain rsh
    joinChannel security rsh
    createChannel blockchain dev
    joinChannel ai dev
    joinChannel blockchain dev
    joinChannel security dev
    createChannel security playground
    joinChannel ai playground
    joinChannel blockchain playground
    joinChannel security playground
    deployCC myChaincode 1.0 1
elif [ "$MODE" == "up" ]; then
    networkUp
elif [ "$MODE" == "down" ]; then
    networkDown
elif [ "$MODE" == "clean" ]; then
    networkDown
    sudo rm -Rf $BDIR
elif [ "$MODE" == "createChannel" ]; then
    createChannel ai rsh
    joinChannel ai rsh
    joinChannel blockchain rsh
    joinChannel security rsh
    createChannel blockchain dev
    joinChannel ai dev
    joinChannel blockchain dev
    joinChannel security dev
    createChannel security playground
    joinChannel ai playground
    joinChannel blockchain playground
    joinChannel security playground
elif [ "$MODE" == "deployCC" ]; then
    deployCC myChaincode 1.0 1
elif [ "$MODE" == "invokeCC" ]; then
    if [ "$QUERY_TYPE" == "" ]; then
        printHelp $MODE
    else
        chaincodeInvoke blockchain dev-channel myChaincode $QUERY_TYPE $PARAMS_ID $PARAMS_COLOR $PARMAS_SIZE $PARAMS_OWNER $PARAMS_VALUE $PARAMS_NEW_OWNER
    fi
elif [ "$MODE" == "queryCC" ]; then
    if [ "$QUERY_TYPE" == "" ]; then
        printHelp $MODE
    else
        chaincodeQuery dev-channel myChaincode $QUERY_TYPE $PARAMS_ID
    fi
elif [ "$MODE" == "test" ]; then
    chaincodeInvoke blockchain dev-channel myChaincode $QUERY_TYPE $PARAMS_ID $PARAMS_COLOR $PARMAS_SIZE $PARAMS_OWNER $PARAMS_VALUE $PARAMS_NEW_OWNER
else
    printHelp
    exit 1
fi
    # if [ "$QUERY_TYPE" == "" ] then

