import SwiftUI

struct AccountCardView: View {
    let account: Account
    let status: AccountRuntimeStatus?
    let onRefresh: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    private var isDark: Bool { colorScheme == .dark }
    
    // 主卡片背景：根据系统浅色/深色自适应
    private var cardBackground: Color {
        isDark ? Color(NSColor.controlBackgroundColor).opacity(0.85) : Color(NSColor.controlBackgroundColor)
    }
    
    // 内嵌模型组背景
    private var groupContainerBackground: Color {
        isDark ? Color.black.opacity(0.28) : Color(NSColor.windowBackgroundColor).opacity(0.75)
    }
    
    // 边框描边
    private var borderColor: Color {
        isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }
    
    // 描述文案颜色：彻底解决深色模式下看不清文字的问题，对比度极佳
    private var descriptionTextColor: Color {
        isDark ? Color(white: 0.88) : Color(white: 0.38)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 1. 账号顶部信息栏（账号名称、绑定邮箱、在线状态）
            accountHeader
            
            // 2. 该账号下的所有模型组（如 Gemini 模型组 + Claude/GPT 模型组）
            let groups = status?.groups ?? account.modelGroups.map { grp in
                ModelGroupRuntimeStatus(
                    id: grp.id,
                    name: grp.name,
                    weeklyQuota: QuotaWindowInfo(title: "剩余周额度", percentage: grp.weeklyPct, resetDescription: grp.weeklyDescription),
                    fiveHourQuota: QuotaWindowInfo(title: "剩余 5 小时限额", percentage: grp.fiveHourPct, resetDescription: grp.fiveHourDescription)
                )
            }
            
            VStack(spacing: 10) {
                ForEach(groups) { group in
                    modelGroupSection(group: group)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(borderColor, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(isDark ? 0.25 : 0.05), radius: 4, x: 0, y: 1)
        )
    }
    
    // 账号信息头部
    private var accountHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: account.provider.iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.accentColor)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(account.name)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color(NSColor.labelColor))
                    
                    if !account.email.isEmpty {
                        Text(account.email)
                            .font(.system(size: 11))
                            .foregroundColor(Color(NSColor.secondaryLabelColor))
                    }
                }
            }
            
            Spacer()
            
            let isConn = status?.isConnected ?? true
            let msg = status?.message ?? "IDE 实时直连"
            HStack(spacing: 4) {
                Circle()
                    .fill(isConn ? Color(red: 0.20, green: 0.82, blue: 0.40) : Color.orange)
                    .frame(width: 6, height: 6)
                Text(msg)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isConn ? Color(red: 0.20, green: 0.82, blue: 0.40) : Color.orange)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill((isConn ? Color.green : Color.orange).opacity(0.12))
            )
        }
        .padding(.horizontal, 2)
    }
    
    // 单个模型组面板（内含 周额度 + 5小时限额 两道进度条）
    private func modelGroupSection(group: ModelGroupRuntimeStatus) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // 模型组标题
            HStack(spacing: 4) {
                Text(group.name)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(NSColor.labelColor))
                
                Button(action: onRefresh) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                        .foregroundColor(Color(NSColor.secondaryLabelColor))
                }
                .buttonStyle(.plain)
                .help("点击核对实时配额")
            }
            .padding(.horizontal, 4)
            
            // 双轨配额容器卡片
            VStack(spacing: 0) {
                quotaRow(info: group.weeklyQuota)
                
                Divider()
                    .opacity(isDark ? 0.2 : 0.4)
                
                quotaRow(info: group.fiveHourQuota)
            }
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(groupContainerBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(borderColor, lineWidth: 0.8)
                    )
            )
        }
    }
    
    // 单行配额度量展示
    private func quotaRow(info: QuotaWindowInfo) -> some View {
        HStack(alignment: .center, spacing: 10) {
            // 左侧：标题与刷新说明文案
            VStack(alignment: .leading, spacing: 3) {
                Text(info.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(NSColor.labelColor))
                
                Text(info.resetDescription)
                    .font(.system(size: 11))
                    .foregroundColor(descriptionTextColor)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer(minLength: 6)
            
            // 右侧：百分比大字 + 环形指示器
            HStack(spacing: 8) {
                Text("\(info.percentage)%")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(Color(NSColor.labelColor))
                    .frame(minWidth: 38, alignment: .trailing)
                
                compactRing(percentage: info.percentage)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
    
    // 紧凑圆环指示器
    private func compactRing(percentage: Int) -> some View {
        let isZero = percentage <= 0
        let ringColor = isZero ? Color(white: isDark ? 0.35 : 0.70) : Color(red: 0.20, green: 0.82, blue: 0.40)
        let ringBg = isDark ? Color(white: 0.22) : Color.black.opacity(0.10)
        
        return ZStack {
            Circle()
                .stroke(ringBg, lineWidth: 3.2)
            
            if !isZero {
                Circle()
                    .trim(from: 0, to: min(max(CGFloat(percentage) / 100.0, 0.05), 1.0))
                    .stroke(
                        ringColor,
                        style: StrokeStyle(lineWidth: 3.2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            } else {
                Circle()
                    .stroke(ringColor, lineWidth: 3.2)
            }
        }
        .frame(width: 22, height: 22)
    }
}
