import Foundation

/// A structure that represents a NetStream's bitRate statics.
public struct NetBitRateStats {
    /// The statistics of outgoing queue bytes per second.
    public let currentQueueBytesOut: Int64
    /// The statistics of incoming bytes per second.
    public let currentBytesInPerSecond: Int32
    /// The statistics of outgoing bytes per second.
    public let currentBytesOutPerSecond: Int32
}

/// A type with a NetStream's bitrate strategy representation.
public protocol NetBitRateStrategyConvertible: AnyObject {
    /// Specifies the stream instance.
    var stream: NetStream? { get set }
    /// The mamimum video bitRate.
    var mamimumVideoBitRate: Int { get }
    /// The mamimum audio bitRate.
    var mamimumAudioBitRate: Int { get }

    /// SetUps the NetBitRateStrategy instance.
    func setUp()
    /// Invoke sufficientBWOccured.
    func sufficientBWOccured(_ stats: NetBitRateStats)
    /// Invoke insufficientBWOccured.
    func insufficientBWOccured(_ stats: NetBitRateStats)
}

/// The NetBitRateStrategy class provides a no operative bitrate storategy.
public final class NetBitRateStrategy: NetBitRateStrategyConvertible {
    public static let shared = NetBitRateStrategy()

    public weak var stream: NetStream?
    public let mamimumVideoBitRate: Int = 0
    public let mamimumAudioBitRate: Int = 0

    public func setUp() {
    }

    public func sufficientBWOccured(_ stats: NetBitRateStats) {
    }

    public func insufficientBWOccured(_ stats: NetBitRateStats) {
    }
}

/// The VideoAdaptiveNetBitRateStrategy class provides an algorithm that focuses on video bitrate control.
public final class VideoAdaptiveNetBitRateStrategy: NetBitRateStrategyConvertible {
    public static let sufficientBWCountsThreshold: Int = 15

    public weak var stream: NetStream?
    public let mamimumVideoBitRate: Int
    public let mamimumAudioBitRate: Int = 0
    private var sufficientBWCounts: Int = 0
    private var zeroBytesOutPerSecondCounts: Int = 0

    public init(mamimumVideoBitrate: Int) {
        self.mamimumVideoBitRate = mamimumVideoBitrate
    }

    public func setUp() {
        zeroBytesOutPerSecondCounts = 0
        stream?.videoSettings.bitRate = mamimumVideoBitRate
    }

    public func sufficientBWOccured(_ stats: NetBitRateStats) {
        guard let stream else {
            return
        }
        if stream.videoSettings.bitRate == mamimumVideoBitRate {
            return
        }
        if Self.sufficientBWCountsThreshold <= sufficientBWCounts {
            let incremental = mamimumVideoBitRate / 10
            stream.videoSettings.bitRate = min(stream.videoSettings.bitRate + incremental, mamimumVideoBitRate)
        } else {
            sufficientBWCounts += 1
        }
    }

    public func insufficientBWOccured(_ stats: NetBitRateStats) {
        guard let stream, 0 < stats.currentBytesOutPerSecond else {
            return
        }
        if 0 < stats.currentBytesOutPerSecond {
            let bitRate = Int(stats.currentBytesOutPerSecond * 8) / (zeroBytesOutPerSecondCounts + 1)
            stream.videoSettings.bitRate = max(bitRate - stream.audioSettings.bitRate, mamimumVideoBitRate / 10)
            stream.videoSettings.frameInterval = 0.0
            sufficientBWCounts = 0
            zeroBytesOutPerSecondCounts = 0
        } else {
            switch zeroBytesOutPerSecondCounts {
            case 2:
                stream.videoSettings.frameInterval = VideoCodecSettings.frameInterval10
            case 4:
                stream.videoSettings.frameInterval = VideoCodecSettings.frameInterval05
            default:
                break
            }
            zeroBytesOutPerSecondCounts += 1
        }
    }
}
