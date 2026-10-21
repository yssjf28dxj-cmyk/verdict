import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_environment.dart';

FirebaseFirestore get appFirestore => FirebaseFirestore.instanceFor(
  app: Firebase.app(),
  databaseId: currentFirestoreDatabaseId(),
);
