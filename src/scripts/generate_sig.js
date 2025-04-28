import { ec, hash } from 'starknet';

// Example private key (replace with a real one for production)
const privateKey = "0x1234567890abcdef1234567890abcdef";
const starknetPublicKey = ec.starkCurve.getStarkKey(privateKey);
const message = [1, 128, 18, 14];
const nonce = "0"; // Initial nonce from test
const msgHash = hash.computeHashOnElements(message);
const signature = ec.starkCurve.sign(msgHash, privateKey);
const { r, s } = signature;

console.log("Public Key (claimed_address):", starknetPublicKey);
console.log("Message Hash:", msgHash);
console.log("r:", r.toString(16));
console.log("s:", s.toString(16));