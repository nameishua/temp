pragma solidity 0.6.4;

import "./lib/Memory.sol";
import "./lib/BytesToTypes.sol";
import "./interface/ILightClient.sol";
import "./interface/ISystemReward.sol";
import "./interface/IParamSubscriber.sol";
import "./System.sol";

contract TendermintLightClient is ILightClient, System, IParamSubscriber {
    struct ConsensusState {
        uint64 preValidatorSetChangeHeight;
        bytes32 appHash;
        bytes32 curValidatorSetHash;
        bytes nextValidatorSet;
    }

    mapping(uint64 => ConsensusState) public lightClientConsensusStates;
    mapping(uint64 => address payable) public submitters;
    uint64 public initialHeight;
    uint64 public latestHeight;
    bytes32 public chainID;

    bytes public constant INIT_CONSENSUS_STATE_BYTES = hex"42696e616e63652d436861696e2d4e696c650000000000000000000000000000000000000000000229eca254b3859bffefaf85f4c95da9fbd26527766b784272789c30ec56b380b6eb96442aaab207bc59978ba3dd477690f5c5872334fc39e627723daa97e441e88ba4515150ec3182bc82593df36f8abb25a619187fcfab7e552b94e64ed2deed000000e8d4a51000";
    uint256 public constant INIT_REWARD_FOR_VALIDATOR_SER_CHANGE = 1e16;
    uint256 public rewardForValidatorSetChange;

    event initConsensusState(uint64 initHeight, bytes32 appHash);
    event syncConsensusState(uint64 height, uint64 preValidatorSetChangeHeight, bytes32 appHash, bool validatorChanged);
    event paramChange(string key, bytes value);

    function init() external onlyNotInit {
        uint256 pointer;
        uint256 length;
        (pointer, length) = Memory.fromBytes(INIT_CONSENSUS_STATE_BYTES);

        /* solium-disable-next-line */
        assembly {
            sstore(chainID_slot, mload(pointer))
        }

        ConsensusState memory cs;
        uint64 height;
        (cs, height) = decodeConsensusState(pointer, length, false);
        cs.preValidatorSetChangeHeight = 0;
        lightClientConsensusStates[height] = cs;

        initialHeight = height;
        latestHeight = height;
        alreadyInit = true;
        rewardForValidatorSetChange = INIT_REWARD_FOR_VALIDATOR_SER_CHANGE;

        emit initConsensusState(initialHeight, cs.appHash);
    }

    function syncTendermintHeader(bytes calldata header, uint64 height) external onlyRelayer returns (bool) {
        require(submitters[height] == address(0x0), "can't sync duplicated header");
        require(height > initialHeight, "can't sync header before initialHeight");

        uint64 preValidatorSetChangeHeight = latestHeight;
        ConsensusState memory cs = lightClientConsensusStates[preValidatorSetChangeHeight];
        for (; preValidatorSetChangeHeight >= height && preValidatorSetChangeHeight >= initialHeight;) {
            preValidatorSetChangeHeight = cs.preValidatorSetChangeHeight;
            cs = lightClientConsensusStates[preValidatorSetChangeHeight];
        }
        if (cs.nextValidatorSet.length == 0) {
            preValidatorSetChangeHeight = cs.preValidatorSetChangeHeight;
            cs.nextValidatorSet = lightClientConsensusStates[preValidatorSetChangeHeight].nextValidatorSet;
            require(cs.nextValidatorSet.length != 0, "failed to load validator set data");
        }

        //32 + 32 + 8 + 32 + 32 + cs.nextValidatorSet.length;
        uint256 length = 136 + cs.nextValidatorSet.length;
        bytes memory input = new bytes(length + header.length);
        uint256 ptr = Memory.dataPtr(input);
        require(
            encodeConsensusState(cs, preValidatorSetChangeHeight, ptr, length), "failed to serialize consensus state"
        );

        // write header to input
        uint256 src;
        ptr = ptr + length;
        (src, length) = Memory.fromBytes(header);
        Memory.copy(src, ptr, length);

        length = input.length + 32;
        // Maximum validator quantity is 99
        bytes32[128] memory result;
        /* solium-disable-next-line */
        assembly {
            // call validateTendermintHeader precompile contract
            // Contract address: 0x64
            if iszero(staticcall(not(0), 0x64, input, length, result, 4096)) { revert(0, 0) }
        }

        //Judge if the validator set is changed
        /* solium-disable-next-line */
        assembly {
            length := mload(add(result, 0))
        }
        bool validatorChanged = false;
        if ((length & (0x01 << 248)) != 0x00) {
            validatorChanged = true;
            ISystemReward(SYSTEM_REWARD_ADDR).claimRewards(msg.sender, rewardForValidatorSetChange);
        }
        length = length & 0xffffffffffffffff;

        /* solium-disable-next-line */
        assembly {
            ptr := add(result, 32)
        }

        uint64 actualHeaderHeight;
        (cs, actualHeaderHeight) = decodeConsensusState(ptr, length, !validatorChanged);
        require(actualHeaderHeight == height, "header height doesn't equal to the specified height");

        submitters[height] = msg.sender;
        cs.preValidatorSetChangeHeight = preValidatorSetChangeHeight;
        lightClientConsensusStates[height] = cs;
        if (height > latestHeight) {
            latestHeight = height;
        }

        emit syncConsensusState(height, preValidatorSetChangeHeight, cs.appHash, validatorChanged);

        return true;
    }

    function isHeaderSynced(uint64 height) external view override returns (bool) {
        return submitters[height] != address(0x0) || height == initialHeight;
    }

    function getAppHash(uint64 height) external view override returns (bytes32) {
        return lightClientConsensusStates[height].appHash;
    }

    function getSubmitter(uint64 height) external view override returns (address payable) {
        return submitters[height];
    }

    function getChainID() external view returns (string memory) {
        bytes memory chainIDBytes = new bytes(32);
        assembly {
            mstore(add(chainIDBytes, 32), sload(chainID_slot))
        }

        uint8 chainIDLength = 0;
        for (uint8 j = 0; j < 32; ++j) {
            if (chainIDBytes[j] != 0) {
                ++chainIDLength;
            } else {
                break;
            }
        }

        bytes memory chainIDStr = new bytes(chainIDLength);
        for (uint8 j = 0; j < chainIDLength; ++j) {
            chainIDStr[j] = chainIDBytes[j];
        }

        return string(chainIDStr);
    }

    // | length   | chainID   | height   | appHash  | curValidatorSetHash | [{validator pubkey, voting power}] |
    // | 32 bytes | 32 bytes   | 8 bytes  | 32 bytes | 32 bytes            | [{32 bytes, 8 bytes}]              |
    /* solium-disable-next-line */
    function encodeConsensusState(
        ConsensusState memory cs,
        uint64 height,
        uint256 outputPtr,
        uint256 size
    ) internal view returns (bool) {
        outputPtr = outputPtr + size - cs.nextValidatorSet.length;

        uint256 src;
        uint256 length;
        (src, length) = Memory.fromBytes(cs.nextValidatorSet);
        Memory.copy(src, outputPtr, length);
        outputPtr = outputPtr - 32;

        bytes32 hash = cs.curValidatorSetHash;
        /* solium-disable-next-line */
        assembly {
            mstore(outputPtr, hash)
        }
        outputPtr = outputPtr - 32;

        hash = cs.appHash;
        /* solium-disable-next-line */
        assembly {
            mstore(outputPtr, hash)
        }
        outputPtr = outputPtr - 32;

        /* solium-disable-next-line */
        assembly {
            mstore(outputPtr, height)
        }
        outputPtr = outputPtr - 8;

        /* solium-disable-next-line */
        assembly {
            mstore(outputPtr, sload(chainID_slot))
        }
        outputPtr = outputPtr - 32;

        // size doesn't contain length
        size = size - 32;
        /* solium-disable-next-line */
        assembly {
            mstore(outputPtr, size)
        }

        return true;
    }

    // | chainID  | height   | appHash  | curValidatorSetHash | [{validator pubkey, voting power}] |
    // | 32 bytes  | 8 bytes  | 32 bytes | 32 bytes            | [{32 bytes, 8 bytes}]              |
    /* solium-disable-next-line */
    function decodeConsensusState(
        uint256 ptr,
        uint256 size,
        bool leaveOutValidatorSet
    ) internal pure returns (ConsensusState memory, uint64) {
        ptr = ptr + 8;
        uint64 height;
        /* solium-disable-next-line */
        assembly {
            height := mload(ptr)
        }

        ptr = ptr + 32;
        bytes32 appHash;
        /* solium-disable-next-line */
        assembly {
            appHash := mload(ptr)
        }

        ptr = ptr + 32;
        bytes32 curValidatorSetHash;
        /* solium-disable-next-line */
        assembly {
            curValidatorSetHash := mload(ptr)
        }

        ConsensusState memory cs;
        cs.appHash = appHash;
        cs.curValidatorSetHash = curValidatorSetHash;

        if (!leaveOutValidatorSet) {
            uint256 dest;
            uint256 length;
            cs.nextValidatorSet = new bytes(size - 104);
            (dest, length) = Memory.fromBytes(cs.nextValidatorSet);

            Memory.copy(ptr + 32, dest, length);
        }

        return (cs, height);
    }

    function updateParam(string calldata key, bytes calldata value) external override onlyInit onlyGov {
        if (Memory.compareStrings(key, "rewardForValidatorSetChange")) {
            require(value.length == 32, "length of rewardForValidatorSetChange mismatch");
            uint256 newRewardForValidatorSetChange = BytesToTypes.bytesToUint256(32, value);
            require(
                newRewardForValidatorSetChange > 0 && newRewardForValidatorSetChange <= 1e18,
                "the newRewardForValidatorSetChange out of range"
            );
            rewardForValidatorSetChange = newRewardForValidatorSetChange;
        } else {
            require(false, "unknown param");
        }
        emit paramChange(key, value);
    }
}
