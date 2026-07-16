// Copyright (c) 2026 Alden Lougee. All rights reserved.
// Proprietary and confidential. Unauthorized copying, modification,
// distribution, or derivative use is prohibited.

import SwiftUI

struct PlanView: View {
    @State private var plans: [PlanEntry] = []
    @State private var newPlanTitle = ""
    @State private var showingNewPlan = false

    var body: some View {
        NavigationStack {
            Group {
                if plans.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(plans) { plan in
                            NavigationLink {
                                PlanDetailView(plan: plan, onSave: { updated in
                                    save(updated)
                                })
                            } label: {
                                planRow(plan)
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Plan")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newPlanTitle = ""
                        showingNewPlan = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .alert("New plan", isPresented: $showingNewPlan) {
                TextField("What are you working toward?", text: $newPlanTitle)
                Button("Create") { createPlan() }
                Button("Cancel", role: .cancel) {}
            }
        }
        .onAppear { plans = PlanStore.shared.loadAll() }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checklist")
                .font(.system(size: 48))
                .foregroundStyle(Color.brandVioletDark)
            Text("No plans yet")
                .font(.title3.weight(.semibold))
            Text("Break a goal into small, literal steps \u{2014} and always know exactly what's next.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
            Button {
                newPlanTitle = ""
                showingNewPlan = true
            } label: {
                Label("New plan", systemImage: "plus")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.brandVioletDark)
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func planRow(_ plan: PlanEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(plan.title).font(.headline)
            if let next = plan.nextStep {
                Text("Next: \(next.text)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if plan.steps.isEmpty {
                Text("No steps yet")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            } else {
                Text("All steps done \u{1F389}")
                    .font(.subheadline)
                    .foregroundStyle(Color.brandGreen)
            }
        }
        .padding(.vertical, 4)
    }

    private func createPlan() {
        let title = newPlanTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let plan = PlanEntry(id: UUID(), title: title, createdAt: Date(), updatedAt: Date(), steps: [])
        save(plan)
    }

    private func save(_ plan: PlanEntry) {
        var updated = plan
        updated.updatedAt = Date()
        PlanStore.shared.save(updated)
        plans = PlanStore.shared.loadAll()
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { PlanStore.shared.delete(id: plans[index].id) }
        plans = PlanStore.shared.loadAll()
    }
}

/// Editing a single plan. The next undone step is always shown first and
/// biggest — the point isn't the list, it's never having to re-figure out
/// what to do right now.
private struct PlanDetailView: View {
    @State private var plan: PlanEntry
    let onSave: (PlanEntry) -> Void
    @State private var newStepText = ""
    @Environment(\.dismiss) private var dismiss

    init(plan: PlanEntry, onSave: @escaping (PlanEntry) -> Void) {
        _plan = State(initialValue: plan)
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section {
                TextField("Plan title", text: $plan.title)
                    .font(.headline)
                    .onChange(of: plan.title) { _, _ in onSave(plan) }
            }

            if let next = plan.nextStep {
                Section("Next step") {
                    Button {
                        toggle(next)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "circle")
                                .foregroundStyle(Color.brandVioletDark)
                            Text(next.text)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } else if !plan.steps.isEmpty {
                Section {
                    Label("All steps done", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(Color.brandGreen)
                }
            }

            Section("All steps") {
                ForEach(plan.steps.indices, id: \.self) { index in
                    HStack(spacing: 10) {
                        Button {
                            toggle(plan.steps[index])
                        } label: {
                            Image(systemName: plan.steps[index].isDone ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(plan.steps[index].isDone ? Color.brandGreen : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        Text(plan.steps[index].text)
                            .strikethrough(plan.steps[index].isDone)
                            .foregroundStyle(plan.steps[index].isDone ? .secondary : .primary)
                    }
                }
                .onDelete { offsets in
                    plan.steps.remove(atOffsets: offsets)
                    onSave(plan)
                }
                .onMove { from, to in
                    plan.steps.move(fromOffsets: from, toOffset: to)
                    onSave(plan)
                }

                HStack {
                    TextField("Add a step\u{2026}", text: $newStepText)
                    Button("Add", action: addStep)
                        .disabled(newStepText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .navigationTitle("Plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
    }

    private func toggle(_ step: PlanStep) {
        guard let idx = plan.steps.firstIndex(where: { $0.id == step.id }) else { return }
        plan.steps[idx].isDone.toggle()
        onSave(plan)
    }

    private func addStep() {
        let text = newStepText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        plan.steps.append(PlanStep(text: text))
        newStepText = ""
        onSave(plan)
    }
}

#Preview { PlanView() }
