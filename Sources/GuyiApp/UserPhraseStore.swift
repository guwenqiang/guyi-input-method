import Foundation
import GuyiCore

@MainActor final class UserPhraseStore {
    static let shared=UserPhraseStore()
    private var phrases=LearnedPhrases()
    private let directory=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("guyi/UserPhrases")
    private var tail: Task<Void,Never>?
    private init() {
        let file=directory.appendingPathComponent("phrases.json")
        if let attributes=try? FileManager.default.attributesOfItem(atPath:file.path),
           attributes[.type] as? FileAttributeType == .typeRegular,
           (attributes[.size] as? Int ?? Int.max)<2_000_000,
           let data=try? Data(contentsOf:file),var saved=try? JSONDecoder().decode(LearnedPhrases.self,from:data),
           saved.entries.count<=2048 {
            saved.compact()
            phrases=saved
        }
    }
    func matches(_ code:String)->[String]{phrases.matches(code)}
    func record(_ code:String,text:String){
        phrases.record(code:code,text:text)
        guard let data=try? JSONEncoder().encode(phrases) else{return}
        let directory=directory,previous=tail
        tail=Task {
            await previous?.value
            await Task.detached {
                do {
                    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
                    let attrs=try FileManager.default.attributesOfItem(atPath:directory.path)
                    guard attrs[.type] as? FileAttributeType == .typeDirectory else{return}
                    let file=directory.appendingPathComponent("phrases.json")
                    if let attrs=try? FileManager.default.attributesOfItem(atPath:file.path),attrs[.type] as? FileAttributeType != .typeRegular{return}
                    try data.write(to:file,options:.atomic)
                    try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
                }catch{}
            }.value
        }
    }
}
