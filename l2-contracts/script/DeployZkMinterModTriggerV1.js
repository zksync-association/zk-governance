"use strict";
var __awaiter = (this && this.__awaiter) || function (thisArg, _arguments, P, generator) {
    function adopt(value) { return value instanceof P ? value : new P(function (resolve) { resolve(value); }); }
    return new (P || (P = Promise))(function (resolve, reject) {
        function fulfilled(value) { try { step(generator.next(value)); } catch (e) { reject(e); } }
        function rejected(value) { try { step(generator["throw"](value)); } catch (e) { reject(e); } }
        function step(result) { result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected); }
        step((generator = generator.apply(thisArg, _arguments || [])).next());
    });
};
var __generator = (this && this.__generator) || function (thisArg, body) {
    var _ = { label: 0, sent: function() { if (t[0] & 1) throw t[1]; return t[1]; }, trys: [], ops: [] }, f, y, t, g = Object.create((typeof Iterator === "function" ? Iterator : Object).prototype);
    return g.next = verb(0), g["throw"] = verb(1), g["return"] = verb(2), typeof Symbol === "function" && (g[Symbol.iterator] = function() { return this; }), g;
    function verb(n) { return function (v) { return step([n, v]); }; }
    function step(op) {
        if (f) throw new TypeError("Generator is already executing.");
        while (g && (g = 0, op[0] && (_ = 0)), _) try {
            if (f = 1, y && (t = op[0] & 2 ? y["return"] : op[0] ? y["throw"] || ((t = y["return"]) && t.call(y), 0) : y.next) && !(t = t.call(y, op[1])).done) return t;
            if (y = 0, t) op = [op[0] & 2, t.value];
            switch (op[0]) {
                case 0: case 1: t = op; break;
                case 4: _.label++; return { value: op[1], done: false };
                case 5: _.label++; y = op[1]; op = [0]; continue;
                case 7: op = _.ops.pop(); _.trys.pop(); continue;
                default:
                    if (!(t = _.trys, t = t.length > 0 && t[t.length - 1]) && (op[0] === 6 || op[0] === 2)) { _ = 0; continue; }
                    if (op[0] === 3 && (!t || (op[1] > t[0] && op[1] < t[3]))) { _.label = op[1]; break; }
                    if (op[0] === 6 && _.label < t[1]) { _.label = t[1]; t = op; break; }
                    if (t && _.label < t[2]) { _.label = t[2]; _.ops.push(op); break; }
                    if (t[2]) _.ops.pop();
                    _.trys.pop(); continue;
            }
            op = body.call(thisArg, _);
        } catch (e) { op = [6, e]; y = 0; } finally { f = t = 0; }
        if (op[0] & 5) throw op[1]; return { value: op[0] ? op[1] : void 0, done: true };
    }
};
Object.defineProperty(exports, "__esModule", { value: true });
var dotenv_1 = require("dotenv");
var hardhat_zksync_deploy_1 = require("@matterlabs/hardhat-zksync-deploy");
var zksync_ethers_1 = require("zksync-ethers");
var ethers_1 = require("ethers");
var hre = require("hardhat");
// Before executing a real deployment, be sure to set these values as appropriate for the environment being deploying
// to. The values used in the script at the time of deployment can be checked in along with the deployment artifacts
// produced by running the scripts.
var ADMIN_ACCOUNT = "0xdEADBEeF00000000000000000000000000000000";
var TOKEN_ADDRESS = "0x99E12239CBf8112fBB3f7Fd473d0558031abcbb5";
var TARGET_ADDRESS = "0x99E12239CBf8112fBB3f7Fd473d0558031abcbb5";
var MERKLE_ROOT = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
var IPFS_HASH = "0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890";
var MINT_AMOUNT = 1000;
var CONTRACT_ABI = [
    "function addMerkleTree(bytes32 merkleRoot, bytes32 ipfsHash, address token, uint256 amount)"
];
var iface = new ethers_1.ethers.Interface(CONTRACT_ABI);
var FUNCTION_SIGNATURE = iface.getSighash("addMerkleTree");
var CALL_DATA = ethers_1.ethers.AbiCoder.defaultAbiCoder().encode(["bytes32", "bytes32", "address", "uint256"], [MERKLE_ROOT, IPFS_HASH, TOKEN_ADDRESS, MINT_AMOUNT]);
function main() {
    return __awaiter(this, void 0, void 0, function () {
        var deployerPrivateKey, contractName, zkWallet, deployer, contract, constructorArgs, distributor, contractAddress;
        return __generator(this, function (_a) {
            switch (_a.label) {
                case 0:
                    (0, dotenv_1.config)();
                    deployerPrivateKey = process.env.DEPLOYER_PRIVATE_KEY;
                    if (!deployerPrivateKey) {
                        throw "Please set DEPLOYER_PRIVATE_KEY in your .env file";
                    }
                    contractName = "ZkMinterModTriggerV1";
                    console.log("Deploying " + contractName + "...");
                    zkWallet = new zksync_ethers_1.Wallet(deployerPrivateKey);
                    deployer = new hardhat_zksync_deploy_1.Deployer(hre, zkWallet);
                    return [4 /*yield*/, deployer.loadArtifact(contractName)];
                case 1:
                    contract = _a.sent();
                    constructorArgs = [ADMIN_ACCOUNT, TOKEN_ADDRESS, TARGET_ADDRESS, FUNCTION_SIGNATURE, CALL_DATA];
                    return [4 /*yield*/, deployer.deploy(contract, constructorArgs)];
                case 2:
                    distributor = _a.sent();
                    console.log("constructor args:" + distributor.interface.encodeDeploy(constructorArgs));
                    return [4 /*yield*/, distributor.getAddress()];
                case 3:
                    contractAddress = _a.sent();
                    console.log("".concat(contractName, " was deployed to ").concat(contractAddress));
                    return [2 /*return*/];
            }
        });
    });
}
main().catch(function (error) {
    console.error(error);
    process.exitCode = 1;
});
