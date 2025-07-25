
create:
	forge create  src/AITaskSolmate.sol:AITaskSolmate \
	--verify \
	--keystore .keystore/dev \
	--broadcast \
	--legacy \
	--rpc-url https://sepolia.metisdevops.link \
	--chain-id 59902 \
	--verifier-url https://api.etherscan.io/v2/api?chainid=59902 \
	--etherscan-api-key D1PM1KBXPNQXFKGQ7E6MGEN6YX7N12NVH7 \
	--constructor-args 0xA2BC39D2b6685Ff752e097143E9d59C2b9Cb4495