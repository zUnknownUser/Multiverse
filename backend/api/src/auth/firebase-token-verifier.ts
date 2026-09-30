import { Inject, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { applicationDefault, getApps, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';

@Injectable()
export class FirebaseTokenVerifier {
  constructor(@Inject(ConfigService) private readonly config: ConfigService) {}
  private auth() {
    const name = 'multiverse-api';
    const app =
      getApps().find((app) => app.name === name) ??
      initializeApp(
        {
          projectId: this.config.get<string>('FIREBASE_PROJECT_ID'),
          credential: applicationDefault(),
        },
        name,
      );
    return getAuth(app);
  }
  verify(token: string) {
    return this.auth().verifyIdToken(token, true);
  }
  async deleteUser(uid: string) {
    try {
      await this.auth().deleteUser(uid);
    } catch (error) {
      if (!(
        typeof error === 'object' &&
        error !== null &&
        'code' in error &&
        error.code === 'auth/user-not-found'
      ))
        throw error;
    }
  }
}
