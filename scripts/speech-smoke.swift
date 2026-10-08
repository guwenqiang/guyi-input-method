import Foundation
import AVFoundation
import GuyiCore

@main struct SpeechSmoke {
    @MainActor static func main() async throws {
        for (language,text) in [(Language.zh,"你好"),(.en,"Hello"),(.id,"Selamat pagi")] {
            guard let voice=AVSpeechSynthesisVoice(language:TranslationSpeech.locale(language)) else {fatalError("Missing voice for \(language)")}
            let synth=AVSpeechSynthesizer()
            let utterance=AVSpeechUtterance(string:text);utterance.voice=voice
            let frames = await withCheckedContinuation { (continuation:CheckedContinuation<Int,Never>) in
                var total=0
                synth.write(utterance) { buffer in
                    guard let pcm=buffer as? AVAudioPCMBuffer else{return}
                    if pcm.frameLength==0 {continuation.resume(returning:total)} else {total += Int(pcm.frameLength)}
                }
            }
            precondition(frames>1000,"Speech synthesis returned no audio")
            print("PASS · Synthesized audio",language.rawValue,voice.language,"frames",frames)
        }
        let speech=TranslationSpeech.shared
        speech.toggle("Hello",language:.en)
        precondition(speech.language == .en)
        speech.toggle("Hello",language:.en)
        precondition(speech.language == nil)
        speech.toggle("Selamat pagi",language:.id)
        precondition(speech.language == .id)
        speech.stop()
        precondition(speech.language == nil)
        print("PASS · Per-language play/stop and replacement state")
    }
}
