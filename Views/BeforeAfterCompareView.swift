import SwiftUI

struct BeforeAfterCompareView: View {
    let original: UIImage
    let generated: UIImage
    @State private var fraction: CGFloat = 0.5

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            ZStack(alignment: .leading) {
                Image(uiImage: original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: width, height: height)

                Image(uiImage: generated)
                    .resizable()
                    .scaledToFit()
                    .frame(width: width, height: height)
                    .mask {
                        HStack(spacing: 0) {
                            Rectangle().frame(width: width * fraction)
                            Spacer(minLength: 0)
                        }
                        .frame(width: width, height: height)
                    }

                Rectangle()
                    .fill(.white)
                    .frame(width: 3, height: height)
                    .position(x: width * fraction, y: height / 2)

                Image(systemName: "arrow.left.and.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 38, height: 38)
                    .background(.white, in: Circle())
                    .position(x: width * fraction, y: height / 2)
            }
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        fraction = min(1, max(0, value.location.x / max(width, 1)))
                    }
            )
            .overlay(alignment: .topLeading) {
                Text("NA")
                    .font(.caption.bold())
                    .padding(7)
                    .background(.black.opacity(0.65), in: Capsule())
                    .padding(10)
            }
            .overlay(alignment: .topTrailing) {
                Text("VOOR")
                    .font(.caption.bold())
                    .padding(7)
                    .background(.black.opacity(0.65), in: Capsule())
                    .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
