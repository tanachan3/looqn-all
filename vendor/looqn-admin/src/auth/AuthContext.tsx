import {
  GoogleAuthProvider,
  getRedirectResult,
  onAuthStateChanged,
  signInWithRedirect,
  signOut,
} from 'firebase/auth'
import type { User } from 'firebase/auth'
import { createContext, useContext, useEffect, useMemo, useState } from 'react'
import { auth } from '../firebase'

export type UserRole = 'operator' | 'admin'

type AuthState = {
  user: User | null
  role: UserRole | null
  loading: boolean
  error: string | null
  signInWithGoogle: () => Promise<void>
  signOutUser: () => Promise<void>
  refreshClaims: () => Promise<void>
}

const AuthContext = createContext<AuthState | undefined>(undefined)

const provider = new GoogleAuthProvider()

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<User | null>(null)
  const [role, setRole] = useState<UserRole | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const refreshClaims = async () => {
    if (!auth.currentUser) {
      setRole(null)
      return
    }
    const tokenResult = await auth.currentUser.getIdTokenResult(true)
    const claimRole = tokenResult.claims.role
    if (claimRole === 'operator' || claimRole === 'admin') {
      setRole(claimRole)
    } else {
      setRole(null)
    }
  }

  useEffect(() => {
    const unsubscribe = onAuthStateChanged(auth, async (nextUser) => {
      setUser(nextUser)
      if (!nextUser) {
        setRole(null)
        setLoading(false)
        return
      }
      try {
        await getRedirectResult(auth)
        await refreshClaims()
        setError(null)
      } catch (err) {
        console.error(err)
        setError('権限情報の取得に失敗しました。')
        setRole(null)
      } finally {
        setLoading(false)
      }
    })

    return () => unsubscribe()
  }, [])

  const signInWithGoogle = async () => {
    try {
      setError(null)
      await signInWithRedirect(auth, provider)
    } catch (err) {
      console.error(err)
      setError('ログインに失敗しました。')
    }
  }

  const signOutUser = async () => {
    try {
      await signOut(auth)
    } catch (err) {
      console.error(err)
      setError('ログアウトに失敗しました。')
    }
  }

  const value = useMemo(
    () => ({
      user,
      role,
      loading,
      error,
      signInWithGoogle,
      signOutUser,
      refreshClaims,
    }),
    [user, role, loading, error],
  )

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth() {
  const context = useContext(AuthContext)
  if (!context) {
    throw new Error('useAuth は AuthProvider の中で利用してください。')
  }
  return context
}
