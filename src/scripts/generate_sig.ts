import { ec, hash, type BigNumberish, type WeierstrassSignatureType, stark } from 'starknet';

const privateKey = '';
const starknetPublicKey = ec.starkCurve.getStarkKey(privateKey);
const fullPublicKey = stark.getFullPublicKey(privateKey);
const str = "hello";
const feltArray = [...str].map(char => char.charCodeAt(0));
const nonce = '0'; // Initial nonce, matches test
const message: BigNumberish[] = [...feltArray, nonce]; // Append nonce

const msgHash = hash.computeHashOnElements(message);
const signature: WeierstrassSignatureType = ec.starkCurve.sign(msgHash, privateKey);

console.log('Public Key (claimed_address):', starknetPublicKey);
console.log('Full Public Key:', fullPublicKey);
console.log('Message Hash:', msgHash);
console.log('r:', '0x' + signature.r.toString(16));
console.log('s:', '0x' + signature.s.toString(16));