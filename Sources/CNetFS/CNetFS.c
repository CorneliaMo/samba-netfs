#include "CNetFS.h"

#include <stdlib.h>
#include <string.h>

static void CNetFSSetError(char **errorMessage, const char *message) {
    if (errorMessage == NULL) {
        return;
    }
    if (message == NULL) {
        *errorMessage = NULL;
        return;
    }
    size_t length = strlen(message);
    char *copy = (char *)malloc(length + 1);
    if (copy == NULL) {
        *errorMessage = NULL;
        return;
    }
    memcpy(copy, message, length + 1);
    *errorMessage = copy;
}

void CNetFSFreeErrorMessage(char *message) {
    free(message);
}

#if defined(__APPLE__)
#include <CoreFoundation/CoreFoundation.h>
#include <NetFS/NetFS.h>

int CNetFSMountURL(
    const char *url,
    const char *mountPath,
    const char *username,
    const char *password,
    char **errorMessage
) {
    if (url == NULL || mountPath == NULL) {
        CNetFSSetError(errorMessage, "url and mountPath are required");
        return -1;
    }

    CFStringRef urlString = CFStringCreateWithCString(kCFAllocatorDefault, url, kCFStringEncodingUTF8);
    CFStringRef pathString = CFStringCreateWithCString(kCFAllocatorDefault, mountPath, kCFStringEncodingUTF8);
    if (urlString == NULL || pathString == NULL) {
        if (urlString != NULL) CFRelease(urlString);
        if (pathString != NULL) CFRelease(pathString);
        CNetFSSetError(errorMessage, "failed to create CoreFoundation strings");
        return -1;
    }

    CFURLRef remoteURL = CFURLCreateWithString(kCFAllocatorDefault, urlString, NULL);
    CFURLRef mountURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, pathString, kCFURLPOSIXPathStyle, true);
    CFRelease(urlString);
    CFRelease(pathString);
    if (remoteURL == NULL || mountURL == NULL) {
        if (remoteURL != NULL) CFRelease(remoteURL);
        if (mountURL != NULL) CFRelease(mountURL);
        CNetFSSetError(errorMessage, "failed to create NetFS URLs");
        return -1;
    }

    CFMutableDictionaryRef options = CFDictionaryCreateMutable(
        kCFAllocatorDefault,
        0,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks
    );
    if (options == NULL) {
        CFRelease(remoteURL);
        CFRelease(mountURL);
        CNetFSSetError(errorMessage, "failed to create NetFS options");
        return -1;
    }

    CFDictionarySetValue(options, kNAUIOptionKey, kNAUIOptionNoUI);

    CFStringRef userString = NULL;
    CFStringRef passwordString = NULL;
    if (username != NULL && strlen(username) > 0) {
        userString = CFStringCreateWithCString(kCFAllocatorDefault, username, kCFStringEncodingUTF8);
    }
    if (password != NULL && strlen(password) > 0) {
        passwordString = CFStringCreateWithCString(kCFAllocatorDefault, password, kCFStringEncodingUTF8);
    }

    CFErrorRef error = NULL;
    int status = NetFSMountURLSync(remoteURL, mountURL, userString, passwordString, NULL, options, &error);
    if (userString != NULL) CFRelease(userString);
    if (passwordString != NULL) CFRelease(passwordString);
    CFRelease(options);
    CFRelease(remoteURL);
    CFRelease(mountURL);

    if (status != 0 || error != NULL) {
        if (error != NULL) {
            CFStringRef description = CFErrorCopyDescription(error);
            if (description != NULL) {
                char buffer[1024];
                if (CFStringGetCString(description, buffer, sizeof(buffer), kCFStringEncodingUTF8)) {
                    CNetFSSetError(errorMessage, buffer);
                } else {
                    CNetFSSetError(errorMessage, "NetFS mount failed");
                }
                CFRelease(description);
            } else {
                CNetFSSetError(errorMessage, "NetFS mount failed");
            }
            CFRelease(error);
        } else {
            CNetFSSetError(errorMessage, "NetFS mount failed");
        }
        return status == 0 ? -1 : status;
    }

    CNetFSSetError(errorMessage, NULL);
    return 0;
}

#else
int CNetFSMountURL(
    const char *url,
    const char *mountPath,
    const char *username,
    const char *password,
    char **errorMessage
) {
    (void)url;
    (void)mountPath;
    (void)username;
    (void)password;
    CNetFSSetError(errorMessage, "NetFS is only available on macOS");
    return -1;
}
#endif
