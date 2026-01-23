import 'package:cloud_firestore/cloud_firestore.dart';

class PenaltyService {
  const PenaltyService();

  static Future<bool> isPenaltyUser(String userId) async {
    try {
      final docRef =
          FirebaseFirestore.instance.collection('users').doc(userId);
      final snapshot =
          await docRef.get(const GetOptions(source: Source.server));
      return snapshot.data()?['is_penalty'] == true;
    } on FirebaseException catch (_) {
      return false;
    } catch (_) {
      return false;
    }
  }

  static Stream<bool> penaltyStream(String userId) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .snapshots()
        .map((snapshot) => snapshot.data()?['is_penalty'] == true)
        .handleError((_) {});
  }
}
