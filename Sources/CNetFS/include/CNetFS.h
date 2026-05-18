#ifndef CNetFS_h
#define CNetFS_h

#ifdef __cplusplus
extern "C" {
#endif

int CNetFSMountURL(
    const char *url,
    const char *mountPath,
    const char *username,
    const char *password,
    char **errorMessage
);

void CNetFSFreeErrorMessage(char *message);

#ifdef __cplusplus
}
#endif

#endif
