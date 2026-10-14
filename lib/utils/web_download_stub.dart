// Stub untuk mobile — tidak pernah dipanggil di mobile
void triggerWebDownload(String url, String filename) =>
    throw UnsupportedError('triggerWebDownload is web-only');

void saveFileWeb(List<int> bytes, String filename) =>
    throw UnsupportedError('saveFileWeb is web-only');
