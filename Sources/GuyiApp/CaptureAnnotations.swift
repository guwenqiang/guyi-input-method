import AppKit
import CoreImage

enum CaptureTool: Int, CaseIterable {
    case selection = 100, rectangle, ellipse, arrow, pen, mosaic, text
    var title: String {
        switch self {
        case .selection: return "选择区域"
        case .rectangle: return "矩形"
        case .ellipse: return "椭圆"
        case .arrow: return "箭头"
        case .pen: return "画笔"
        case .mosaic: return "马赛克"
        case .text: return "文字"
        }
    }
    var symbol: String {
        switch self {
        case .selection: return "cursorarrow"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .arrow: return "arrow.up.right"
        case .pen: return "pencil.tip"
        case .mosaic: return "square.grid.3x3.fill"
        case .text: return "textformat"
        }
    }
}

struct CaptureMark {
    let tool: CaptureTool
    var points: [NSPoint]
    var color: NSColor
    var width: CGFloat
    var text = ""
    var rect: NSRect {
        guard let a = points.first, let b = points.last else { return .zero }
        return NSRect(x: min(a.x,b.x), y: min(a.y,b.y), width: abs(a.x-b.x), height: abs(a.y-b.y))
    }
    func draw(pixelated: NSImage?, bounds: NSRect) {
        guard let start = points.first, let end = points.last else { return }
        color.setStroke()
        color.setFill()
        let path = NSBezierPath()
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        switch tool {
        case .rectangle: path.appendRect(rect); path.stroke()
        case .ellipse: path.appendOval(in: rect); path.stroke()
        case .pen:
            path.move(to:start)
            for point in points.dropFirst() { path.line(to:point) }
            if points.count == 1 { path.line(to:NSPoint(x:start.x+0.1,y:start.y)) }
            path.stroke()
        case .arrow:
            path.move(to:start);path.line(to:end);path.stroke()
            let angle = atan2(end.y-start.y,end.x-start.x), length = max(12,width*4)
            let head=NSBezierPath();head.move(to:end)
            head.line(to:NSPoint(x:end.x-length*cos(angle-0.45),y:end.y-length*sin(angle-0.45)))
            head.line(to:NSPoint(x:end.x-length*cos(angle+0.45),y:end.y-length*sin(angle+0.45)))
            head.close();head.fill()
        case .mosaic:
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect:rect).addClip()
            pixelated?.draw(in:bounds)
            NSGraphicsContext.restoreGraphicsState()
        case .text:
            (text as NSString).draw(in:NSRect(x:start.x,y:start.y-120,width:max(80,bounds.maxX-start.x),height:120),
                withAttributes:[.font:NSFont.systemFont(ofSize:max(16,width*6)),.foregroundColor:color])
        case .selection: break
        }
    }
}
