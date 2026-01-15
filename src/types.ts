import { Timestamp } from 'firebase/firestore'

export type PostStatus = 'active' | 'hidden' | 'deleted' | 'under_review'

export type ReportState = 'open' | 'resolved' | 'rejected'

export type InquiryState = 'new' | 'assigned' | 'waiting_user' | 'done'

export type Post = {
  id: string
  status?: PostStatus
  createdAt?: Timestamp
  expiresAt?: Timestamp
  reportCount?: number
  lastReportedAt?: Timestamp
}

export type Report = {
  id: string
  postId: string
  reasonCode?: string
  reporterUid?: string | null
  createdAt?: Timestamp
  state?: ReportState
}

export type Inquiry = {
  id: string
  fromUid?: string | null
  category?: string
  state?: InquiryState
  assigneeUid?: string | null
  lastMessageAt?: Timestamp
}

export type InquiryMessage = {
  id: string
  inquiryId: string
  senderType: 'user' | 'operator'
  text: string
  createdAt?: Timestamp
}

export type ModerationAction = {
  id: string
  targetType: 'post' | 'inquiry'
  targetId: string
  action: string
  reasonCode?: string | null
  note?: string | null
  operatorUid: string
  operatorEmail?: string | null
  createdAt?: Timestamp
}
