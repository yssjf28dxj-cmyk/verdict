import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_session.dart';
import 'firebase_environment.dart';

FirebaseFirestore get appFirestore => FirebaseFirestore.instanceFor(
  app: activeFirebaseApp,
  databaseId: currentFirestoreDatabaseId(),
);
