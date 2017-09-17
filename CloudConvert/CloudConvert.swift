//
//  CloudConvert.swift
//
//  Copyright (c) 2015 CloudConvert (https://cloudconvert.com/)
//
//    Permission is hereby granted, free of charge, to any person obtaining a copy
//    of this software and associated documentation files (the "Software"), to deal
//    in the Software without restriction, including without limitation the rights
//    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//    copies of the Software, and to permit persons to whom the Software is
//    furnished to do so, subject to the following conditions:
//
//    The above copyright notice and this permission notice shall be included in
//    all copies or substantial portions of the Software.
//
//    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//    THE SOFTWARE.
//
//
//  Created by Josias Montag on 03.04.15.
//

import Foundation
import Alamofire

extension String: Error {}

public let apiProtocol = "https"
public let apiHost = "api.cloudconvert.com"
public var apiKey: String = "" {
    didSet {
        // reset manager instance because we need a new auth header
        managerInstance = nil
    }
}

public let errorDomain = "com.cloudconvert.error"

// MARK: - Request

private var managerInstance: Alamofire.SessionManager?
private var manager: Alamofire.SessionManager {
    if managerInstance != nil {
        return managerInstance!
    }
    // let configuration = NSURLSessionConfiguration.backgroundSessionConfigurationWithIdentifier("com.cloudconvert.background")
    let configuration = URLSessionConfiguration.default
    configuration.httpAdditionalHeaders = [
        "Authorization": "Bearer " + apiKey,
    ]
    managerInstance = Alamofire.SessionManager(configuration: configuration)
    return managerInstance!
}

/**

 Creates a NSURLRequest for API Requests

 :param: URLString   The URL String, can be relative to api Host
 :param: parameters  Dictionary of Query String (GET) or JSON Body (POST) parameters

 :returns: NSURLRequest

 */
private func urlRequest(_ method: Alamofire.HTTPMethod, urlString: String) throws -> URLRequest {
    var urlString = urlString
    if urlString.hasPrefix("//") {
        urlString = apiProtocol + ":" + urlString
    } else if !urlString.hasPrefix("http") {
        urlString = apiProtocol + "://" + apiHost + urlString
    }

    var urlRequest: URLRequest = try URLRequest(url: urlString.asURL())
    urlRequest.httpMethod = method.rawValue

    return urlRequest
}

/**

 Wrapper for Alamofire.request()

 :param: method      HTTP Method (.GET, .POST...)
 :param: URLString   The URL String, can be relative to api Host
 :param: parameters  Dictionary of Query String (GET) or JSON Body (POST) parameters

 :returns: Alamofire.Request

 */
@discardableResult
public func req(_ method: Alamofire.HTTPMethod, urlString: String, parameters: [String: AnyObject]? = nil) throws -> Alamofire.DataRequest {
    var encoding: Alamofire.ParameterEncoding = URLEncoding(destination: .queryString)
    if method == .post {
        encoding = JSONEncoding.default
    }

    return try manager.request(encoding.encode(urlRequest(method, urlString: urlString), with: parameters))
}

/**

 Wrapper for Alamofire.upload()

 :param: URLString   The URL String, can be relative to api Host
 :param: parameters  Dictionary of Query String parameters
 :param: file        The NSURL to the local file to upload

 :returns: Alamofire.Request

 */

public func upload(_ urlString: String, parameters: [String: AnyObject]? = nil, file: URL) throws -> Alamofire.UploadRequest {
    let encoding: Alamofire.ParameterEncoding = URLEncoding(destination: .queryString)
    let request: URLRequestConvertible = try encoding.encode(urlRequest(.put, urlString: urlString), with: parameters)
    return manager.upload(file, with: request)
}

/**

 Wrapper for Alamofire.download()

 :param: URLString   The URL String, can be relative to api Host
 :param: parameters  Dictionary of Query String parameters
 :param: destination Closure to generate the destination NSURL

 :returns: Alamofire.Request

 */
public func download(_ urlString: String, parameters: [String: AnyObject]? = nil, destination: @escaping DownloadRequest.DownloadFileDestination) throws -> Alamofire.DownloadRequest {

    let encoding: Alamofire.ParameterEncoding = URLEncoding(destination: .queryString)
    let request: URLRequestConvertible = try encoding.encode(urlRequest(.get, urlString: urlString), with: parameters)

    return manager.download(request, to: destination)
}

/**

 Response Serializer for the CloudConvert API

 */

extension Alamofire.DataRequest {
    /// Creates a response serializer that returns the associated data as-is.
    ///
    /// - returns: A data response serializer.
    public static func dataResponseSerializer() -> DataResponseSerializer<Data> {
        return DataResponseSerializer { _, response, data, error in
            Request.serializeResponseData(response: response, data: data, error: error)
        }
    }

    /// Adds a handler to be called once the request has finished.
    ///
    /// - parameter completionHandler: The code to be executed once the request has finished.
    ///
    /// - returns: The request.
    @discardableResult
    public func responseData(
        queue: DispatchQueue? = nil,
        completionHandler: @escaping (DataResponse<Data>) -> Void)
        -> Self {
        return response(
            queue: queue,
            responseSerializer: DataRequest.dataResponseSerializer(),
            completionHandler: completionHandler
        )
    }
}

extension Alamofire.DataRequest {

    public static func cloudConvertResponseSerializer(
        options: JSONSerialization.ReadingOptions = .allowFragments)
        -> DataResponseSerializer<Any> {
        return DataResponseSerializer { _, response, data, error in
            guard error == nil else { return .failure(error!) }

            let result = Request.serializeResponseJSON(options: options, response: response, data: data, error: error)

            switch result {
            case let .success(value):
                if let response = response {
                    if !(200 ..< 300).contains(response.statusCode) {
                        return .failure(AFError.responseValidationFailed(reason: .unacceptableStatusCode(code: response.statusCode)))
                    } else {
                        return .success(value)
                    }
                } else {
                    return .failure(AFError.responseSerializationFailed(reason: .jsonSerializationFailed(error: "Error serializing json")))
                }
            case let .failure(error):
                return .failure(error)
            }
        }
    }

    /// Adds a handler to be called once the request has finished.
    ///
    /// - parameter completionHandler: The code to be executed once the request has finished.
    ///
    /// - returns: The request.

    @discardableResult
    public func responseCloudConvertApi(
        queue: DispatchQueue? = nil,
        completionHandler: @escaping (DataResponse<Any>) -> Void)
        -> Self {
        return response(
            queue: queue,
            responseSerializer: Alamofire.DataRequest.cloudConvertResponseSerializer(),
            completionHandler: completionHandler
        )
    }
}

// MARK: - Process

public protocol ProcessDelegate {
    /**

     Monitor conversion progress

     :param: process     The CloudConvert.Process
     :param: step        Current step of the process; see https://cloudconvert.com/apidoc#status
     :param: percent     Percentage (0-100) of the current step as Float value
     :param: message     Description of the current progress

     */
    func conversionProgress(_ process: Process, step: String?, percent: Float?, message: String?)

    /**

     Conversion completed on server side. This happens before the output file was downloaded!

     :param: process     The CloudConvert.Process
     :param: error       NSError object if the conversion failed

     */
    func conversionCompleted(_ process: Process?, error: Error?)

    /**

     Conversion output file was downloaded to local path

     :param: process     The CloudConvert.Process
     :param: path        NSURL of the downloaded output file

     */
    func conversionFileDownloaded(_ process: Process?, path: URL)
}

open class Process: NSObject {

    open var delegate: ProcessDelegate?
    open var url: String?

    fileprivate var data: [String: Any?]? = [:] {
        didSet {
            if let url = data?["url"] as? String {
                self.url = url
            }
        }
    }

    fileprivate var currentRequest: Alamofire.Request?
    fileprivate var waitCompletionHandler: ((Error?) -> Void)?
    fileprivate var progressHandler: ((_ step: String?, _ percent: Float?, _ message: String?) -> Void)?
    fileprivate var refreshTimer: Timer?

    subscript(name: String) -> Any? {
        return data?[name]!
    }

    override init() {
    }

    init(url: String) {
        self.url = url
    }

    /**

     Create Process on the CloudConvert API

     :param: parameters          Dictionary of parameters. See: https://cloudconvert.com/apidoc#create
     :param: completionHandler   The code to be executed once the request has finished.

     :returns: CloudConvert.Process

     */
    @discardableResult
    public func create(_ parameters: [String: AnyObject], completionHandler: @escaping (Error?) -> Void) throws -> Self {
        var parameters = parameters

        parameters.removeValue(forKey: "file")
        parameters.removeValue(forKey: "download")

        try req(.post, urlString: "/process", parameters: parameters)
            .responseCloudConvertApi { response -> Void in
                if let error = response.error {
                    completionHandler(error as NSError)
                } else if let url = (response.value as? [String: Any?])?["url"] as? String {
                    self.url = url
                    completionHandler(nil)
                } else {
                    completionHandler(NSError(domain: errorDomain, code: -1, userInfo: nil))
                }
            }
        return self
    }

    /**

     Refresh process data from API

     :param: parameters          Dictionary of Query String parameters
     :param: completionHandler   The code to be executed once the request has finished.

     :returns: CloudConvert.Process

     */
    @discardableResult
    open func refresh(_ parameters: [String: AnyObject]? = nil, completionHandler: ((Error?) -> Void)? = nil) throws -> Self {

        if currentRequest != nil {
            // if there is a active refresh request, cancel it
            currentRequest!.cancel()
        }

        if url == nil {
            completionHandler?(NSError(domain: errorDomain, code: -1, userInfo: ["localizedDescription": "No Process URL!"]))
            return self
        }

        currentRequest = try CloudConvert
            .req(.get, urlString: url!, parameters: parameters)
            .responseCloudConvertApi { response -> Void in
                self.currentRequest = nil
                if let error = response.error {
                    completionHandler?(error as NSError)
                } else {
                    self.data = response.value as? [String: Any?]
                    completionHandler?(nil)
                }

                self.progressHandler?(self.data?["step"] as? String, self.data?["percent"] as? Float, self.data?["message"] as? String)
                self.delegate?.conversionProgress(self, step: self.data?["step"] as? String, percent: self.data?["percent"] as? Float, message: self.data?["message"] as? String)

                if response.error != nil || self.data?["step"] as? String == "finished" {
                    // conversion finished
                    DispatchQueue.main.async {
                        self.refreshTimer?.invalidate()
                        self.refreshTimer = nil
                    }

                    self.waitCompletionHandler?(response.error)
                    self.waitCompletionHandler = nil

                    self.delegate?.conversionCompleted(self, error: response.error)
                }
            }
        return self
    }

    /**

     Starts the conversion on the CloudConvert API

     :param: parameters          Dictionary of parameters. See: https://cloudconvert.com/apidoc#start
     :param: completionHandler   The code to be executed once the request has finished.

     :returns: CloudConvert.Process

     */
    @discardableResult
    public func start(_ parameters: [String: AnyObject], completionHandler: ((NSError?) -> Void)?) throws -> Self {
        var parameters = parameters

        if url == nil {
            completionHandler?(NSError(domain: errorDomain, code: -1, userInfo: ["localizedDescription": "No Process URL!"]))
            return self
        }

        let file: URL? = parameters["file"] as? URL

        let startRequestComplete: (DataResponse<Any>) -> Void = { response -> Void in
            self.currentRequest = nil
            if let error = response.error {
                completionHandler?(error as NSError)
            } else {
                self.data = response.value as? [String: Any?]

                if file != nil && (parameters["input"] as? String) == "upload" {
                    self.upload(file!, completionHandler: completionHandler)
                } else {
                    completionHandler?(nil)
                }
            }
        }

        parameters.removeValue(forKey: "download")

        if file != nil {
            parameters["file"] = file!.absoluteString as AnyObject
        }
        currentRequest = try CloudConvert
            .req(.post, urlString: url!, parameters: parameters)
            .responseCloudConvertApi(completionHandler: startRequestComplete)

        return self
    }

    /**

     Uploads an input file to the CloudConvert API

     :param: uploadPath        Local path of the input file.
     :param: completionHandler   The code to be executed once the upload has finished.

     :returns: CloudConvert.Process

     */

    @discardableResult
    public func upload(_ uploadPath: URL, completionHandler: ((NSError?) -> Void)?) -> Self {
        let uploadPath = uploadPath

        if let upload = self.data?["upload"] as? NSDictionary, var url = upload["url"] as? String {
            url += "/" + uploadPath.lastPathComponent

            let formatter = ByteCountFormatter()
            formatter.allowsNonnumericFormatting = false

            currentRequest = try?
                CloudConvert
                .upload(url, file: uploadPath)
                .uploadProgress { progress in

                    let percent: Float = Float(progress.fractionCompleted * 100)
                    let message = "Uploading (\(percent)%) ..."
                    self.delegate?.conversionProgress(self, step: "upload", percent: percent, message: message)
                    self.progressHandler?("upload", percent, message)
                }
                .responseCloudConvertApi { response -> Void in
                    self.currentRequest = nil
                    if let error = response.error {
                        completionHandler?(error as NSError)
                    } else {
                        completionHandler?(nil)
                    }
                }

        } else {
            completionHandler?(NSError(domain: errorDomain, code: -1, userInfo: ["localizedDescription": "File cannot be uploaded in this process state!"]))
        }

        return self
    }

    /**

     Downloads the output file from the CloudConvert API

     :param: downloadPath        Local path for downloading the output file.
     If set to nil a temporary location will be choosen.
     Can be set to a directory or a file. Any existing file will be overwritten.
     :param: completionHandler   The code to be executed once the download has finished.

     :returns: CloudConvert.Process

     */
    @discardableResult
    public func download(_ downloadPath: URL? = nil, completionHandler: ((URL?, Error?) -> Void)?) -> Self {
        var downloadPath = downloadPath

        if let output = self.data?["output"] as? NSDictionary, let url = output["url"] as? String {

            let formatter = ByteCountFormatter()
            formatter.allowsNonnumericFormatting = false

            currentRequest = try? CloudConvert
                .download(url, parameters: nil, destination: { temporaryURL, response in

                    var isDirectory: ObjCBool = false

                    if downloadPath != nil && isDirectory.boolValue {
                        // downloadPath is a directory
                        let downloadName = response.suggestedFilename!
                        downloadPath = downloadPath!.appendingPathComponent(downloadName)
                        do {
                            try FileManager.default.removeItem(at: downloadPath!)
                        } catch _ {
                        }
                        return (destinationURL: downloadPath!, options: DownloadRequest.DownloadOptions(rawValue: 3))
                    } else if downloadPath != nil {
                        // downloadPath is a file
                        let exists = FileManager.default.fileExists(atPath: downloadPath!.path, isDirectory: &isDirectory)
                        if exists {
                            do {
                                try FileManager.default.removeItem(at: downloadPath!)
                            } catch _ {
                            }
                        }
                        return (destinationURL: downloadPath!, options: DownloadRequest.DownloadOptions(rawValue: 3))
                    } else {
                        // downloadPath not set
                        if let directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                            let downloadName = response.suggestedFilename!
                            downloadPath = directoryURL.appendingPathComponent(downloadName)
                            do {
                                try FileManager.default.removeItem(at: downloadPath!)
                            } catch _ {
                            }
                            return (destinationURL: downloadPath!, options: DownloadRequest.DownloadOptions(rawValue: 3))
                        }
                    }

                    return (destinationURL: temporaryURL, options: DownloadRequest.DownloadOptions(rawValue: 3))
                }).downloadProgress { progress in

                    let percent: Float = Float(progress.fractionCompleted * 100)
                    let message = "Downloading (\(percent)%) ..."
                    self.delegate?.conversionProgress(self, step: "download", percent: percent, message: message)
                    self.progressHandler?("download", percent, message)

                }.responseData { response in
                    self.progressHandler?("finished", 100, "Conversion finished!")
                    self.delegate?.conversionProgress(self, step: "finished", percent: 100, message: "Conversion finished!")

                    completionHandler?(downloadPath, response.result.error)
                    self.delegate?.conversionFileDownloaded(self, path: downloadPath!)
                }

        } else {
            completionHandler?(nil, NSError(domain: errorDomain, code: -1, userInfo: ["localizedDescription": "Output file not yet available!"]))
        }
        return self
    }

    /**

     Waits until the conversion has finished

     :param: completionHandler   The code to be executed once the conversion has finished.

     :returns: CloudConvert.Process

     */
    @discardableResult
    open func wait(_ completionHandler: ((Error?) -> Void)?) -> Self {

        waitCompletionHandler = completionHandler
        DispatchQueue.main.async(execute: {
            self.refreshTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self as Process, selector: #selector(Process.refreshTimerTick), userInfo: nil, repeats: true)
        })

        return self
    }

    @objc open func refreshTimerTick() {
        _ = try? refresh()
    }

    /**

     Cancels the conversion, including any running upload or download.
     Also deletes the process from the CloudConvert API.

     :returns: CloudConvert.Process

     */
    @discardableResult
    open func cancel() throws -> Self {

        currentRequest?.cancel()
        currentRequest = nil

        DispatchQueue.main.async(execute: {
            self.refreshTimer?.invalidate()
            self.refreshTimer = nil
        })

        if url != nil {
            _ = try? CloudConvert.req(.delete, urlString: url!, parameters: nil)
        }

        return self
    }

    // Printable
    open override var description: String {
        return "Process " + (url != nil ? url! : "") + " " + (data != nil ? data!.description : "")
    }
}

// MARK: - Methods

/**

 Converts a file using the CloudConvert API.

 :param: parameters          Parameters for the conversion.
 Can be generated using the API Console: https://cloudconvert.com/apiconsole

 :param: progressHandler     Can be used to monitor the progress of the conversion.
 Parameters of the Handler:
 step:        Current step of the process; see https://cloudconvert.com/apidoc#status ;
 percent:     Percentage (0-100) of the current step as Float value;
 message:     Description of the current progress

 :param: completionHandler   The code to be executed once the conversion has finished.
 Parameters of the Handler:
 path:       local NSURL of the downloaded output file;
 error:      NSError if the conversion failed

 :returns: A CloudConvert.Porcess object, which can be used to cancel the conversion.

 */
@discardableResult
public func convert(_ parameters: [String: AnyObject], progressHandler: ((_ step: String?, _ percent: Float?, _ message: String?) -> Void)? = nil, completionHandler: ((URL?, Error?) -> Void)? = nil) throws -> Process {

    let process = Process()
    process.progressHandler = progressHandler

    try process.create(parameters, completionHandler: { (error) -> Void in
        do {
            if error != nil {
                completionHandler?(nil, error)
            } else {
                try process.start(parameters, completionHandler: { (error) -> Void in
                    if error != nil {
                        completionHandler?(nil, error)
                    } else {
                        process.wait({ (error) -> Void in
                            if error != nil {
                                completionHandler?(nil, error)
                            } else {
                                if let download = parameters["download"] as? URL {
                                    process.download(download, completionHandler: completionHandler)
                                } else if let download = parameters["download"] as? String, download != "false" {
                                    process.download(completionHandler: completionHandler)
                                } else if let download = parameters["download"] as? Bool, download != false {
                                    process.download(completionHandler: completionHandler)
                                } else {
                                    completionHandler?(nil, nil)
                                }
                            }
                        })
                    }
                })
            }
        } catch {
        }
    })

    return process
}

/**

 Find possible conversion types.

 :param: parameters          Find conversion types for a specific inputformat and/or outputformat.
 For example: ["inputformat" : "png"]
 See https://cloudconvert.com/apidoc#types
 :param: completionHandler   The code to be executed once the request has finished.

 */
public func conversionTypes(_ parameters: [String: AnyObject], completionHandler: @escaping (Array<[String: AnyObject]>?, Error?) -> Void) throws {
    try req(.get, urlString: "/conversiontypes", parameters: parameters)
        .responseCloudConvertApi { response -> Void in
            if let types = response.value as? Array<[String: AnyObject]> {
                completionHandler(types, nil)
            } else {
                completionHandler(nil, response.error)
            }
        }
}
