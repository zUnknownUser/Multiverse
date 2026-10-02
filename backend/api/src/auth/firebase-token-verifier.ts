import { Inject, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  applicationDefault,
  cert,
  getApps,
  initializeApp,
} from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';

@Injectable()
export class FirebaseTokenVerifier {
  constructor(@Inject(ConfigService) private readonly config: ConfigService) {}
  app() {
    const name = 'multiverse-api';
    const app =
      getApps().find((app) => app.name === name) ??
      initializeApp(
        {
          projectId: this.config.get<string>('FIREBASE_PROJECT_ID'),
          credential: this.credential(),
        },
        name,
      );
    return app;
  }
  private auth() {
    return getAuth(this.app());
  }
  private credential() {
    const json = this.config.get<string>('FIREBASE_SERVICE_ACCOUNT_JSON');
    if (!json) return applicationDefault();
    try {
      const account = JSON.parse(json) as Record<string, unknown>;
      if (
        account.project_id !== this.config.get<string>('FIREBASE_PROJECT_ID') ||
        typeof account.client_email !== 'string' ||
        typeof account.private_key !== 'string'
      )
        throw new Error('Invalid service account');
      return cert({
        projectId: account.project_id as string,
        clientEmail: account.client_email,
        privateKey: account.private_key,
      });
    } catch {
      // Do not include credential contents or parser errors in logs.
      throw new Error('Invalid FIREBASE_SERVICE_ACCOUNT_JSON configuration');
    }
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
