const PASSPHRASE = 'your-secret-passphrase'
const FIXED_IV = '16charsfixediv!!'

const textEncoder = new TextEncoder()
const textDecoder = new TextDecoder()
let cachedKey: Promise<CryptoKey> | null = null

const base64UrlToBytes = (value: string) => {
  const padded = value.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(value.length / 4) * 4, '=')
  const binary = atob(padded)
  return Uint8Array.from(binary, (char) => char.charCodeAt(0))
}

const hexString = (bytes: Uint8Array) =>
  Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('')

const getKey = () => {
  if (cachedKey) return cachedKey
  cachedKey = crypto.subtle.digest('SHA-256', textEncoder.encode(PASSPHRASE)).then((hash) => {
    const hex = hexString(new Uint8Array(hash)).slice(0, 32)
    const keyBytes = textEncoder.encode(hex)
    return crypto.subtle.importKey('raw', keyBytes, { name: 'AES-CBC' }, false, ['decrypt'])
  })
  return cachedKey
}

const decryptWithIv = async (encrypted: string, iv: Uint8Array) => {
  const key = await getKey()
  const encryptedBytes = base64UrlToBytes(encrypted)
  const decrypted = await crypto.subtle.decrypt({ name: 'AES-CBC', iv }, key, encryptedBytes)
  return textDecoder.decode(decrypted)
}

export const decryptText = async (encrypted: string) => {
  try {
    const decoded = base64UrlToBytes(encrypted)
    if (decoded.length < 17) {
      return encrypted
    }
    const iv = decoded.slice(0, 16)
    const payload = decoded.slice(16)
    const key = await getKey()
    const decrypted = await crypto.subtle.decrypt({ name: 'AES-CBC', iv }, key, payload)
    return textDecoder.decode(decrypted)
  } catch (error) {
    console.error(error)
    return encrypted
  }
}

export const decryptUserId = async (encrypted: string) => {
  try {
    const iv = textEncoder.encode(FIXED_IV)
    return await decryptWithIv(encrypted, iv)
  } catch (error) {
    console.error(error)
    return encrypted
  }
}
