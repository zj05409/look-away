import CoreAudio
import Foundation

@MainActor
final class MicrophoneMonitor: ObservableObject {
    @Published private(set) var isMicActive = false

    private var deviceListenerBlocks: [AudioDeviceID: AudioObjectPropertyListenerBlock] = [:]
    private var hardwareListenerBlock: AudioObjectPropertyListenerBlock?

    init() {
        startMonitoring()
    }

    private func startMonitoring() {
        refreshMicState()
        attachHardwareListener()
        attachInputDeviceListeners()
    }

    private func attachHardwareListener() {
        guard hardwareListenerBlock == nil else { return }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.attachInputDeviceListeners()
            }
        }
        hardwareListenerBlock = block

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
    }

    private func attachInputDeviceListeners() {
        let inputDeviceIDs = Self.inputDeviceIDs()

        for (deviceID, block) in deviceListenerBlocks where !inputDeviceIDs.contains(deviceID) {
            removeDeviceListener(deviceID: deviceID, block: block)
            deviceListenerBlocks.removeValue(forKey: deviceID)
        }

        for deviceID in inputDeviceIDs where deviceListenerBlocks[deviceID] == nil {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.refreshMicState()
                }
            }
            deviceListenerBlocks[deviceID] = block
            AudioObjectAddPropertyListenerBlock(deviceID, &address, DispatchQueue.main, block)
        }

        refreshMicState()
    }

    private func removeDeviceListener(deviceID: AudioDeviceID, block: @escaping AudioObjectPropertyListenerBlock) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(deviceID, &address, DispatchQueue.main, block)
    }

    private func refreshMicState() {
        let active = Self.checkMicrophoneInUse()
        guard active != isMicActive else { return }
        isMicActive = active
    }

    nonisolated static func checkMicrophoneInUse() -> Bool {
        inputDeviceIDs().contains { isDeviceRunning($0) }
    }

    nonisolated private static func inputDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        ) == noErr, dataSize > 0 else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceIDs
        ) == noErr else {
            return []
        }

        return deviceIDs.filter(isInputDevice)
    }

    nonisolated private static func isInputDevice(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr, dataSize > 0 else {
            return false
        }

        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { bufferList.deallocate() }

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, bufferList) == noErr else {
            return false
        }

        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        return buffers.contains { $0.mNumberChannels > 0 }
    }

    nonisolated private static func isDeviceRunning(_ deviceID: AudioDeviceID) -> Bool {
        var isRunning: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &isRunning) == noErr else {
            return false
        }
        return isRunning != 0
    }
}
