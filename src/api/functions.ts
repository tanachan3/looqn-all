import { httpsCallable } from 'firebase/functions'
import { functions } from '../firebase'

export type ModeratePostPayload = {
  postId: string
  action: 'hide' | 'restore' | 'delete'
  reasonCode?: string
  note?: string
}

export type ReplyInquiryPayload = {
  inquiryId: string
  text: string
}

export type UpdateInquiryPayload = {
  inquiryId: string
  state?: string
  assigneeUid?: string
}

export const moderatePost = async (payload: ModeratePostPayload) => {
  const callable = httpsCallable(functions, 'moderatePost')
  return callable(payload)
}

export const replyInquiry = async (payload: ReplyInquiryPayload) => {
  const callable = httpsCallable(functions, 'replyInquiry')
  return callable(payload)
}

export const updateInquiry = async (payload: UpdateInquiryPayload) => {
  const callable = httpsCallable(functions, 'updateInquiry')
  return callable(payload)
}
