import { HTTPError } from 'ky';

type ErrorBody = {
  message?: unknown;
  errors?: unknown;
  detail?: unknown;
};

function text(value: unknown): string | undefined {
  if (value === undefined || value === null) {
    return undefined;
  }

  if (Array.isArray(value)) {
    return text(value[0]);
  }

  if (typeof value === 'object') {
    return text(Object.values(value)[0]);
  }

  return String(value);
}

function firstError(errors: unknown): string | undefined {
  if (!errors) {
    return undefined;
  }

  if (Array.isArray(errors)) {
    return text(errors[0]);
  }

  if (typeof errors === 'object') {
    return text(Object.values(errors)[0]);
  }

  return text(errors);
}

export async function getHTTPErrorMessage(error: unknown, fallback = 'Bad request'): Promise<string> {
  if (error instanceof HTTPError) {
    try {
      const body = (await error.response.json()) as ErrorBody;
      const message = text(body.message) || text(body.detail) || firstError(body.errors);
      if (message) {
        return message;
      }
    } catch {
      return fallback;
    }
  }

  if (error instanceof Error && error.message) {
    return error.message;
  }

  return fallback;
}
