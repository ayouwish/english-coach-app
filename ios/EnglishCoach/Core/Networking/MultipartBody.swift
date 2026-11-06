import Foundation

/// 已经构造好的 multipart 请求体：字节 + boundary（Content-Type 由它拼出）。
struct MultipartBody: Sendable {
    let boundary: String
    let data: Data

    var contentType: String {
        "multipart/form-data; boundary=\(boundary)"
    }
}

/// 手写 multipart/form-data。录音（≤12MB）用内存 Data 足够；
/// 书页 OCR 等大图后续再切换成临时文件 + uploadTask。
struct MultipartFormDataBuilder {
    private let boundary = "Boundary-\(UUID().uuidString)"
    private var data = Data()

    mutating func addField(name: String, value: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        data.append(Data(value.utf8))
        append("\r\n")
    }

    mutating func addFile(name: String, filename: String, mimeType: String, data fileData: Data) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        data.append(fileData)
        append("\r\n")
    }

    mutating func finalize() -> MultipartBody {
        append("--\(boundary)--\r\n")
        return MultipartBody(boundary: boundary, data: data)
    }

    private mutating func append(_ string: String) {
        data.append(Data(string.utf8))
    }
}
