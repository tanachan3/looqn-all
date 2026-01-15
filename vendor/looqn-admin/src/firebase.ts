import { initializeApp } from 'firebase/app'
import { getAnalytics } from 'firebase/analytics'
import { getAuth } from 'firebase/auth'
import { getFirestore } from 'firebase/firestore'
import { getFunctions } from 'firebase/functions'

const resolveEnv = (value: string | undefined, fallback: string) => {
  if (!value) return fallback
  if (value.startsWith('your-')) return fallback
  return value
}

const firebaseConfig = {
  apiKey: resolveEnv(
    import.meta.env.VITE_FIREBASE_API_KEY,
    'AIzaSyCmSs3uKuLP3pQfDC2Yc32ID2puQOXxwoA',
  ),
  authDomain: resolveEnv(
    import.meta.env.VITE_FIREBASE_AUTH_DOMAIN,
    'geomsg-4d728.firebaseapp.com',
  ),
  projectId: resolveEnv(import.meta.env.VITE_FIREBASE_PROJECT_ID, 'geomsg-4d728'),
  storageBucket: resolveEnv(
    import.meta.env.VITE_FIREBASE_STORAGE_BUCKET,
    'geomsg-4d728.firebasestorage.app',
  ),
  messagingSenderId: resolveEnv(import.meta.env.VITE_FIREBASE_MESSAGING_SENDER_ID, '756158976086'),
  appId: resolveEnv(
    import.meta.env.VITE_FIREBASE_APP_ID,
    '1:756158976086:web:d79868640fa9a84f4debf7',
  ),
  measurementId: resolveEnv(import.meta.env.VITE_FIREBASE_MEASUREMENT_ID, 'G-HBB58RTE0Z'),
}

const app = initializeApp(firebaseConfig)

export const auth = getAuth(app)
export const db = getFirestore(app)
export const functions = getFunctions(app)
export const analytics =
  typeof window !== 'undefined' ? getAnalytics(app) : undefined
