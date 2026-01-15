import { Timestamp } from 'firebase/firestore'

export const formatTimestamp = (value?: Timestamp | null) => {
  if (!value) {
    return '-'
  }
  return value.toDate().toLocaleString('ja-JP')
}
